// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "./support/Test.sol";
import {SqueekChain} from "../src/SqueekChain.sol";

/// @dev Models a contract deploying the token in one transaction, as the launch factory does.
contract SqueekChainDeployer {
    function deploy() external returns (SqueekChain) {
        return new SqueekChain();
    }
}

/// @notice Boundary cases, authorization isolation and atomic rollback beyond the basic ERC-20 tests.
/// forge-config: default.fuzz.runs = 1000
contract SqueekChainEdgeTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 private constant SUPPLY = 1e27;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA201);

    SqueekChain private token;

    function setUp() public {
        token = new SqueekChain();
    }

    function test_contractDeployerReceivesExactlyOneMint() public {
        SqueekChainDeployer factory = new SqueekChainDeployer();
        vm.recordLogs();
        vm.prank(ALICE);
        SqueekChain deployed = factory.deploy();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(deployed.totalSupply(), SUPPLY, "one billion tokens with 18 decimals");
        assertEq(deployed.balanceOf(address(factory)), SUPPLY, "the immediate creator receives the mint");
        assertEq(deployed.balanceOf(ALICE), 0, "the factory caller receives no mint");
        assertEq(deployed.balanceOf(address(this)), 0, "the outer caller receives no mint");
        assertEq(logs.length, 1, "one constructor mint event");
        assertEq(logs[0].emitter, address(deployed), "the token emits the mint");
        assertEq(logs[0].topics.length, 3, "Transfer has two indexed addresses");
        assertEq(
            uint256(logs[0].topics[0]), uint256(keccak256("Transfer(address,address,uint256)")), "Transfer signature"
        );
        assertEq(uint256(logs[0].topics[1]), 0, "mint from zero");
        assertEq(uint256(logs[0].topics[2]), uint256(uint160(address(factory))), "mint to creator");
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY, "mint event value");
    }

    function test_oneWeiCanBeTransferredAndReturned() public {
        assertTrue(token.transfer(ALICE, 1), "smallest unit transfers");
        assertEq(token.balanceOf(ALICE), 1, "one minor unit arrives");
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), 1), "smallest unit returns");
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_maximumTransferRevertsWithoutChangingBalances() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SqueekChain.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_selfTransferStillRequiresEnoughBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(SqueekChain.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_zeroValueDoesNotMakeZeroRecipientValid() public {
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), BOB), 0, "failed zero transfer creates no approval");
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        token.approve(BOB, 123);
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0, "zero spender remains unapproved");
        assertEq(token.allowance(address(this), BOB), 123, "existing approval survives");
    }

    /// @dev Zero cannot originate a real transaction; these calls exercise the defensive guards only.
    function test_zeroCallerGuards() public {
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(ALICE, 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_transferFromCannotSourceTheZeroAddress() public {
        // No zero-address approval can exist. Reject both zero and positive amounts without
        // coupling this property to the order of allowance and sender validation.
        vm.expectRevert();
        token.transferFrom(address(0), ALICE, 0);
        vm.expectRevert();
        token.transferFrom(address(0), ALICE, 1);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_exactAllowanceCanBeSpentInPartsButCannotBeReplayed() public {
        token.approve(BOB, 10);
        vm.startPrank(BOB);
        assertTrue(token.transferFrom(address(this), ALICE, 3), "first spend");
        assertTrue(token.transferFrom(address(this), ALICE, 7), "last authorized spend");
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        vm.stopPrank();
        assertEq(token.allowance(address(this), BOB), 0, "finite approval exhausted exactly");
        _assertBalances(SUPPLY - 10, 10, 0);
    }

    function test_unlimitedApprovalCanBeRevokedAfterSpending() public {
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), BOB, 0);
        assertTrue(token.approve(BOB, 0), "revocation succeeds");

        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), BOB), 0, "revoked unlimited approval stays zero");
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_maximumMinusOneIsFiniteAndDecreases() public {
        token.approve(BOB, type(uint256).max - 1);
        vm.prank(BOB);
        assertTrue(token.transferFrom(address(this), ALICE, 1), "spend against large finite approval");
        assertEq(token.allowance(address(this), BOB), type(uint256).max - 2, "only max is infinite");
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_unlimitedAllowanceDoesNotBypassBalanceChecks() public {
        token.approve(BOB, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                SqueekChain.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), BOB), type(uint256).max, "failed spend preserves infinite approval");
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_selfTransferFromConsumesAllowanceWithoutMovingTokens() public {
        token.approve(BOB, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        vm.prank(BOB);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY), "authorized self transfer");
        assertEq(token.allowance(address(this), BOB), 0, "self transfer consumes finite approval");
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_ownerUsingTransferFromNeedsItsOwnApproval() public {
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), ALICE, 1), "self approval authorizes transferFrom");
        assertEq(token.allowance(address(this), address(this)), 0, "self approval consumed");
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_zeroTransferFromNeedsNoBalanceOrApprovalAndEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, CAROL, 0);
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, CAROL, 0), "zero delegated transfer from an empty owner");
        assertEq(token.allowance(ALICE, BOB), 0, "no approval created");
        assertEq(token.balanceOf(CAROL), 0, "no tokens created");
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_approvalsAreIsolatedByBothOwnerAndSpender() public {
        token.transfer(ALICE, 10);
        token.approve(BOB, 3);
        token.approve(CAROL, 7);
        vm.prank(ALICE);
        token.approve(BOB, 5);

        vm.prank(BOB);
        assertTrue(token.transferFrom(address(this), BOB, 3), "spender can be the recipient");
        assertEq(token.allowance(address(this), BOB), 0, "only the spent pair changes");
        assertEq(token.allowance(address(this), CAROL), 7, "other spender is isolated");
        assertEq(token.allowance(ALICE, BOB), 5, "other owner is isolated");
        assertEq(token.allowance(BOB, address(this)), 0, "reverse pair is isolated");
        assertEq(token.balanceOf(CAROL), 0, "approval creates no balance");
        _assertBalances(SUPPLY - 13, 10, 3);
    }

    function test_fullSupplyCanMoveThroughAnApprovedSpender() public {
        token.approve(BOB, SUPPLY);
        vm.prank(BOB);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY), "whole supply transfers exactly");
        assertEq(token.allowance(address(this), BOB), 0, "whole approval consumed");
        _assertBalances(0, SUPPLY, 0);
    }

    function testFuzz_roundTripRestoresBalancesButNotSpentAllowance(uint256 seed) public {
        uint256 amount = bound(seed, 0, SUPPLY);
        token.approve(BOB, amount);
        vm.prank(BOB);
        assertTrue(token.transferFrom(address(this), ALICE, amount), "authorized outbound transfer");
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), amount), "return transfer");
        _assertBalances(SUPPLY, 0, 0);
        assertEq(token.allowance(address(this), BOB), 0, "returning tokens does not replenish an approval");
    }

    function testFuzz_approvalReplacementIsIdempotent(uint256 first, uint256 replacement) public {
        token.approve(BOB, first);
        token.approve(BOB, replacement);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), BOB, replacement);
        assertTrue(token.approve(BOB, replacement), "repeated approval succeeds");
        assertEq(token.allowance(address(this), BOB), replacement, "approval replaces rather than adds");
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_reducingApprovalImmediatelyLimitsSpending(uint256 oldSeed, uint256 newSeed) public {
        uint256 oldApproval = bound(oldSeed, 1, SUPPLY);
        uint256 newApproval = bound(newSeed, 0, oldApproval - 1);
        token.approve(BOB, oldApproval);
        token.approve(BOB, newApproval);
        vm.expectRevert(
            abi.encodeWithSelector(SqueekChain.ERC20InsufficientAllowance.selector, BOB, newApproval, newApproval + 1)
        );
        vm.prank(BOB);
        token.transferFrom(address(this), ALICE, newApproval + 1);
        assertEq(token.allowance(address(this), BOB), newApproval, "failed spend preserves the reduced approval");
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_insufficientBalanceRollsBackFiniteAllowance(uint256 balanceSeed, uint256 amountSeed) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
        token.transfer(ALICE, balance);
        vm.prank(ALICE);
        token.approve(BOB, amount);

        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, amount);
        assertEq(token.allowance(ALICE, BOB), amount, "allowance deduction is rolled back with the transfer");
        assertEq(token.balanceOf(CAROL), 0, "failed transfer credits no recipient");
        _assertBalances(SUPPLY - balance, balance, 0);
    }

    function testFuzz_zeroRecipientRollsBackAllowance(uint256 amountSeed, uint256 approvalSeed) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 approval = bound(approvalSeed, amount, type(uint256).max);
        token.approve(BOB, approval);
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), BOB), approval, "invalid destination preserves approval");
        _assertBalances(SUPPLY, 0, 0);
    }

    function _assertBalances(uint256 deployer, uint256 alice, uint256 bob) private view {
        assertEq(token.balanceOf(address(this)), deployer, "deployer balance");
        assertEq(token.balanceOf(ALICE), alice, "alice balance");
        assertEq(token.balanceOf(BOB), bob, "bob balance");
        assertEq(token.balanceOf(address(0)), 0, "no tokens at zero");
        assertEq(token.totalSupply(), SUPPLY, "fixed supply");
    }
}
