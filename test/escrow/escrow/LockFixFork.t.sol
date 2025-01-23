/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, console2 as console} from "forge-std/Test.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";

import {MockERC20} from "@mocks/MockERC20.sol";
import {createTestDAO} from "@mocks/MockDAO.sol";

import "@helpers/OSxHelpers.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {IVotingEscrowEventsStorageErrorsEvents} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";
import {IWhitelistErrors, IWhitelistEvents} from "@escrow-interfaces/ILock.sol";
import {Lock as LockNew} from "@escrow/Lock.sol";
import {Lock} from "@escrow/LockOld.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";
import {QuadraticIncreasingEscrow} from "@escrow/QuadraticIncreasingEscrow.sol";
import {ExitQueue} from "@escrow/ExitQueue.sol";
import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "src/voting/SimpleGaugeVoterSetup.sol";
import {Clock} from "@clock/Clock.sol";

/**
 
  Aim for tonight: have the tx to rollback all 4 contracts done in the mode msig 
   - have it signed on aragon multisig (carlos, jordan, javier)
   - have the upgrade script loaded up
   - new branch 
   - merged  
   - fork tested
   - send to auditors the script and ensure they check the corresponding test files
   - the man who makes the best paella, his name is 

  **/
contract LockTestFixFork is
    Test,
    IVotingEscrowEventsStorageErrorsEvents,
    IWhitelistErrors,
    IWhitelistEvents
{
    using ProxyLib for address;
    string name = "Voting Escrow";
    string symbol = "VE";

    MockPluginSetupProcessor psp;
    MockDAOFactory daoFactory;
    MockERC20 token;

    Lock nftLock;
    VotingEscrow escrow;
    QuadraticIncreasingEscrow curve;
    SimpleGaugeVoter voter;
    ExitQueue queue;
    Clock clock;

    DAO dao;
    Multisig multisig;
    MultisigSetup multisigSetup;
    address deployer = address(this);

    error OnlyEscrow();

    function testItWorksOnAFork() public {
        // staked and voting
        address staked = address(0xE28842dAF2cDe94EecC81b26A436eB043454F010);
        uint stakedNFT = 21453;
        address modeHolder = address(0x57bc397F100a376F33567Bb69E8E4F1d4552F81E);
        address exiting = address(0x8A0c098e896fa309828A35Ce714403D23cBBCf3A);
        uint modeHolderNFT;
        uint modeBalance = token.balanceOf(modeHolder);
        uint exitingNFT = 25841;

        console.log("escrow in lock", address(nftLock.escrow()));

        vm.warp(block.timestamp + 1 weeks);

        // mode holder cant create lock
        vm.startPrank(modeHolder);
        {
            token.approve(address(escrow), modeBalance);
            vm.expectRevert(OnlyEscrow.selector);
            escrow.createLock(modeBalance);
        }
        vm.stopPrank();

        // staked can't begin withdraw
        vm.startPrank(staked);
        {
            nftLock.approve(address(escrow), stakedNFT);
            vm.expectRevert(NotWhitelisted.selector);
            escrow.resetVotesAndBeginWithdrawal(stakedNFT);
        }
        vm.stopPrank();

        // exiting cant exit
        vm.startPrank(exiting);
        {
            vm.expectRevert(OnlyEscrow.selector);
            escrow.withdraw(exitingNFT);
        }
        vm.stopPrank();

        // downgrade the contract to the non fucked up one
        Lock impl = Lock(0x643561CAe8F05f449dC30C3cE52E253e81d75340);
        assertEq(address(nftLock.dao()), address(escrow.dao()));
        vm.startPrank(address(nftLock.dao()));
        {
            nftLock.upgradeTo(address(impl));
        }
        vm.stopPrank();
        console.log("escrow in lock", address(nftLock.escrow()));
        console.log("escrow whitelisted", nftLock.whitelisted(address(escrow)));

        // mode holder can create lock
        vm.startPrank(modeHolder);
        {
            token.approve(address(escrow), modeBalance);
            modeHolderNFT = escrow.createLock(modeBalance);
        }
        vm.stopPrank();

        // staked can begin withdraw
        vm.startPrank(staked);
        {
            nftLock.approve(address(escrow), stakedNFT);
            escrow.resetVotesAndBeginWithdrawal(stakedNFT);
        }
        vm.stopPrank();

        // exiting can exit
        vm.startPrank(exiting);
        {
            escrow.withdraw(exitingNFT);
        }
        vm.stopPrank();

        // flow through rest of lifecycle
        vm.warp(block.timestamp + 1 weeks);

        vm.startPrank(staked);
        {
            escrow.withdraw(stakedNFT);
        }
        vm.stopPrank();

        vm.startPrank(modeHolder);
        {
            nftLock.approve(address(escrow), modeHolderNFT);
            escrow.beginWithdrawal(modeHolderNFT);
        }
        vm.stopPrank();

        vm.warp(block.timestamp + 1 weeks);

        vm.startPrank(modeHolder);
        {
            escrow.withdraw(modeHolderNFT);
        }
        vm.stopPrank();
    }

    function setUp() public virtual {
        /**
| Contract | Address | Description |
| --- | --- | --- |
| Voting Escrow | 0xff8AB822b8A853b01F9a9E9465321d6Fe77c9D2F | Main Staking contract for the  tokens. In most cases you will be calling this contract for staking data and computing voting power. |
| Gauge Voter | 0x71439Ae82068E19ea90e4F506c74936aE170Cf58 | Gauge Voting Contract that users will cast votes against when voting for emissions. In most cases you will be calling this data for checking gauge data. |
| Escrow Curve | 0x69E57EE7782701DdA44b170Df5b1244C6F02e89b | Contains Logic for calculating voting power change over time and stores checkpoint data |
| Exit Queue | 0x915e50A7C53e05F72122bC883309a812A90bA163 | Controls cooldowns, min locks and exit mechanisms for those looking to unstake. |
| Clock | 0x66CC481755f8a9d415e75d29C17B0E3eF2Af70bD | Unified contract that tracks epochs, checkpoint intervals and voting windows. |
| veNFT Lock | 0x06ab1Dc3c330E9CeA4fDF0C7C6F6Fb6442A4273C | ERC721 Representation of a staking position.  |
| Stake Inspector | 0xB508d9Cd504C740C0C3a7c708F7154c2FC978D16 | Simple view function to query aggregate staked tokens |
	*/
        escrow = VotingEscrow(0xff8AB822b8A853b01F9a9E9465321d6Fe77c9D2F);
        curve = QuadraticIncreasingEscrow(0x69E57EE7782701DdA44b170Df5b1244C6F02e89b);
        voter = SimpleGaugeVoter(0x71439Ae82068E19ea90e4F506c74936aE170Cf58);
        queue = ExitQueue(0x915e50A7C53e05F72122bC883309a812A90bA163);
        clock = Clock(0x66CC481755f8a9d415e75d29C17B0E3eF2Af70bD);
        nftLock = Lock(0x06ab1Dc3c330E9CeA4fDF0C7C6F6Fb6442A4273C);
        token = MockERC20(0xDfc7C877a950e49D2610114102175A06C2e3167a);
    }

    function _authErr(
        address _caller,
        address _contract,
        bytes32 _perm
    ) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                DaoUnauthorized.selector,
                address(dao),
                _contract,
                _caller,
                _perm
            );
    }

    function _deployEscrow(
        address _token,
        address _dao,
        address _clock,
        uint256 _minDeposit
    ) public returns (VotingEscrow) {
        VotingEscrow impl = new VotingEscrow();

        bytes memory initCalldata = abi.encodeCall(
            VotingEscrow.initialize,
            (_token, _dao, _clock, _minDeposit)
        );
        return VotingEscrow(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployLock(
        address _escrow,
        string memory _name,
        string memory _symbol,
        address _dao
    ) public returns (Lock) {
        Lock impl = new Lock();

        bytes memory initCalldata = abi.encodeWithSelector(
            Lock.initialize.selector,
            _escrow,
            _name,
            _symbol,
            _dao
        );
        return Lock(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployCurve(
        address _escrow,
        address _dao,
        uint48 _warmup,
        address _clock
    ) public returns (QuadraticIncreasingEscrow) {
        QuadraticIncreasingEscrow impl = new QuadraticIncreasingEscrow();

        bytes memory initCalldata = abi.encodeCall(
            QuadraticIncreasingEscrow.initialize,
            (_escrow, _dao, _warmup, _clock)
        );
        return QuadraticIncreasingEscrow(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployVoter(
        address _dao,
        address _escrow,
        bool _reset,
        address _clock
    ) public returns (SimpleGaugeVoter) {
        SimpleGaugeVoter impl = new SimpleGaugeVoter();

        bytes memory initCalldata = abi.encodeCall(
            SimpleGaugeVoter.initialize,
            (_dao, _escrow, _reset, _clock)
        );
        return SimpleGaugeVoter(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployExitQueue(
        address _escrow,
        uint48 _cooldown,
        address _dao,
        uint256 _feePercent,
        address _clock,
        uint48 _minLock
    ) public returns (ExitQueue) {
        ExitQueue impl = new ExitQueue();

        bytes memory initCalldata = abi.encodeCall(
            ExitQueue.initialize,
            (_escrow, _cooldown, _dao, _feePercent, _clock, _minLock)
        );
        return ExitQueue(address(impl).deployUUPSProxy(initCalldata));
    }

    function _deployClock(address _dao) internal returns (Clock) {
        address impl = address(new Clock());
        bytes memory initCalldata = abi.encodeWithSelector(Clock.initialize.selector, _dao);
        return Clock(impl.deployUUPSProxy(initCalldata));
    }

    function _deployOSX() internal {
        // deploy the mock PSP with the multisig  plugin
        multisigSetup = new MultisigSetup();
        psp = new MockPluginSetupProcessor(address(multisigSetup));
        daoFactory = new MockDAOFactory(psp);
    }

    function _deployDAO() internal {
        dao = createTestDAO(deployer);
    }
}
