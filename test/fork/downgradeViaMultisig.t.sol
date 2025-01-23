// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {Multisig} from "@aragon/multisig/Multisig.sol";
import {VotingEscrow, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {GaugesDaoFactory, GaugePluginSet, DeploymentParameters, Deployment, TokenParameters, DAO} from "src/factory/GaugesDaoFactory.sol";
import {IGaugeVote} from "@voting/ISimpleGaugeVoter.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

uint256 constant PROPOSAL_ID = 48; // pinned to block on mainnet
contract TestDowngradeViaMultisig is Test {
    GaugesDaoFactory factory;
    GaugePluginSet modePluginSet;
    GaugePluginSet bptPluginSet;

    /// @dev Mode multisig executing via the dao
    Multisig modeMultisig;

    /// @dev Mode dao owning the contracts
    DAO modeDAO;

    /// @dev Aragon signer multisig on the mode multisig
    Multisig aragonMultisig = Multisig(address(0x4315B4D2C707981f7fA51DBE91079Ea8c44e2e95));

    Lock lockMode;
    Lock lockBPT;
    SimpleGaugeVoter voterMode;
    SimpleGaugeVoter voterBPT;

    address lockModeImplOld = address(0x643561CAe8F05f449dC30C3cE52E253e81d75340);
    address lockBPTImplOld = address(0x643561CAe8F05f449dC30C3cE52E253e81d75340);
    address voterModeImplOld = address(0x2f21661f0EE08e5397e2e734fB162E8871a5F765);
    address voterBPTImplOld = address(0x2f21661f0EE08e5397e2e734fB162E8871a5F765);

    address[] aragonSigners;
    address[] modeSigners;

    MockERC20 token = MockERC20(0xDfc7C877a950e49D2610114102175A06C2e3167a);
    error OnlyEscrow();
    error NotWhitelisted();

    // metadata for the proposal, pinned to pinata
    bytes ipfsURI = bytes("ipfs://bafkreifbolvifin7oomrsdxnf6nej46mwka6oh3yon4yxdwkpdq7ku62wq");

    function setAragonSigners() internal {
        aragonSigners.push(address(0x946138B088524414EEDaf0699BA10d7Fb5673A34));
        aragonSigners.push(address(0xbd3eE47A1576F26454C65B96b7AbfaF8Ee9cB4a1));
        aragonSigners.push(address(0x3ffe3F16d47A54b1C6A3f47c9E6Ff5C2C1B32859));
        aragonSigners.push(address(0x9395e6b95afFee7d7b2b107127Fcc9e4167A336f));
    }

    function setModeSigners() internal {
        address[] memory signers = readMultisigMembers();
        for (uint256 i = 0; i < signers.length; i++) {
            modeSigners.push(signers[i]);
        }
    }

    // hardcoded staker, may or may not be voting at block
    function getStaker(string memory _network) public view returns (address staker) {
        if (isMainnet(_network)) return 0xE28842dAF2cDe94EecC81b26A436eB043454F010;
        else if (isTestnet(_network)) return 0x8bF0280B2557B98532EC21e6c070Dba1bFAaDbf2;
        else revert("Invalid network");
    }

    function readMultisigMembers() public view returns (address[] memory result) {
        // JSON list of members
        string memory membersFilePath = vm.envString("MULTISIG_MEMBERS_JSON_FILE_NAME");
        string memory path = string.concat(vm.projectRoot(), membersFilePath);
        string memory strJson = vm.readFile(path);

        bool exists = vm.keyExistsJson(strJson, "$.members");
        if (!exists) revert("EmptyMultisig()");

        result = vm.parseJsonAddressArray(strJson, "$.members");

        if (result.length == 0) revert("EmptyMultisig()");
    }

    function _retrieveDeployment(address _factoryAddress) internal {
        factory = GaugesDaoFactory(_factoryAddress);
        Deployment memory deployment = factory.getDeployment();
        modePluginSet = deployment.gaugeVoterPluginSets[0];
        bptPluginSet = deployment.gaugeVoterPluginSets[1];
        modeMultisig = deployment.multisigPlugin;
        modeDAO = deployment.dao;

        // bind the voter and lock contracts
        lockMode = modePluginSet.nftLock;
        lockBPT = bptPluginSet.nftLock;

        voterMode = modePluginSet.plugin;
        voterBPT = bptPluginSet.plugin;
    }

    function testDowngrade() public {
        setModeSigners();
        setAragonSigners();

        _retrieveDeployment(vm.envAddress("FACTORY_ADDRESS"));
        string memory network = vm.envString("NETWORK");

        testBeforeDowngrade();

        uint proposalId;
        IDAO.Action[] memory actions = buildActions();
        if (isMainnet(network)) {
            vm.startPrank(aragonSigners[0]);
            uint256 aragonProposalId = _createAragonMsigProposal(actions);
            vm.stopPrank();
            _executeAragonProposal(aragonProposalId);
            proposalId = PROPOSAL_ID;
        } else if (isTestnet(network)) {
            vm.startPrank(modeSigners[0]);
            proposalId = _buildMsigProposal(
                actions,
                modeSigners,
                modeMultisig,
                vm.envOr("TRY_EXECUTE", false)
            );
            vm.stopPrank();
        } else {
            revert("Invalid network");
        }

        _signExecuteMultisigProposal(proposalId, modeSigners, modeMultisig);

        testAfterDowngrade();
    }
    function testBeforeDowngrade() public {
        // staked and voting
        address staked = address(0xE28842dAF2cDe94EecC81b26A436eB043454F010);
        uint stakedNFT = 21453;
        address modeHolder = address(0x57bc397F100a376F33567Bb69E8E4F1d4552F81E);
        address exiting = address(0x8A0c098e896fa309828A35Ce714403D23cBBCf3A);
        uint modeHolderNFT;
        uint modeBalance = token.balanceOf(modeHolder);
        uint exitingNFT = 25841;

        Lock nftLock = lockMode;
        VotingEscrow escrow = modePluginSet.votingEscrow;

        console.log("escrow in lock", address(nftLock.escrow()));
        console.log("escrow whitelisted", nftLock.whitelisted(address(escrow)));

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
    }

    function testAfterDowngrade() public {
        // staked and voting
        address staked = address(0xE28842dAF2cDe94EecC81b26A436eB043454F010);
        uint stakedNFT = 21453;
        address modeHolder = address(0x57bc397F100a376F33567Bb69E8E4F1d4552F81E);
        address exiting = address(0x8A0c098e896fa309828A35Ce714403D23cBBCf3A);
        uint modeHolderNFT;
        uint modeBalance = token.balanceOf(modeHolder);
        uint exitingNFT = 25841;

        Lock nftLock = lockMode;
        VotingEscrow escrow = modePluginSet.votingEscrow;

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

    function _createAragonMsigProposal(
        IDAO.Action[] memory _actions
    ) internal returns (uint256 proposalId) {
        IDAO.Action[] memory outerAction = new IDAO.Action[](1);

        outerAction[0] = IDAO.Action({
            to: address(modeMultisig),
            value: 0,
            data: abi.encodeCall(
                modeMultisig.createProposal,
                (ipfsURI, _actions, 0, true, false, 0, uint64(block.timestamp) + 1 weeks)
            )
        });

        // need to build on aragon first
        proposalId = _buildMsigProposal(outerAction, aragonSigners, aragonMultisig, false);
    }

    function _executeAragonProposal(uint outerId) internal {
        _signExecuteMultisigProposal(outerId, aragonSigners, aragonMultisig);
    }

    function isMainnet(string memory _network) internal view returns (bool) {
        return strEq(_network, "mode") || strEq(_network, "mode-mainnet");
    }

    function isTestnet(string memory _network) internal view returns (bool) {
        return strEq(_network, "mode-sepolia");
    }

    function buildActions() internal returns (IDAO.Action[] memory) {
        // action 2: upgradeTo
        IDAO.Action[] memory actions = new IDAO.Action[](4);
        actions[0] = IDAO.Action({
            to: address(lockMode),
            value: 0,
            data: abi.encodeCall(lockMode.upgradeTo, (lockModeImplOld))
        });

        actions[1] = IDAO.Action({
            to: address(voterMode),
            value: 0,
            data: abi.encodeCall(voterMode.upgradeTo, (voterModeImplOld))
        });

        actions[2] = IDAO.Action({
            to: address(lockBPT),
            value: 0,
            data: abi.encodeCall(lockBPT.upgradeTo, (lockBPTImplOld))
        });

        actions[3] = IDAO.Action({
            to: address(voterBPT),
            value: 0,
            data: abi.encodeCall(voterBPT.upgradeTo, (voterBPTImplOld))
        });

        return actions;
    }

    function _buildMsigProposal(
        IDAO.Action[] memory _actions,
        address[] memory _signers,
        Multisig _multisig,
        bool _tryExecution
    ) internal returns (uint256 proposalId) {
        {
            proposalId = _multisig.createProposal({
                _metadata: ipfsURI,
                _actions: _actions,
                _allowFailureMap: 0,
                _approveProposal: true,
                _tryExecution: _tryExecution,
                _startDate: 0,
                _endDate: uint64(block.timestamp) + 1 weeks
            });
        }

        return proposalId;
    }

    function _signExecuteMultisigProposal(
        uint256 _proposalId,
        address[] memory _signers,
        Multisig _multisig
    ) internal {
        // load all the proposers into memory other than the first
        if (_signers.length > 1) {
            // have them sign
            for (uint256 i = 1; i < _signers.length; i++) {
                vm.startPrank(_signers[i]);
                {
                    _multisig.approve(_proposalId, false);
                }
                vm.stopPrank();
            }
        }

        // prank the first signer who will create stuff
        vm.startPrank(_signers[0]);
        {
            _multisig.execute(_proposalId);
        }
        vm.stopPrank();
    }

    function strEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
