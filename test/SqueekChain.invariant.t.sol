// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "./support/Test.sol";
import {SqueekChain} from "../src/SqueekChain.sol";
import {SqueekChainHandler} from "./handlers/SqueekChainHandler.sol";

/// @notice Stateful conservation, ownership and allowance properties under mixed valid and invalid calls.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract SqueekChainInvariantTest is Test {
    uint256 private constant SUPPLY = 1e27;
    uint256 private constant SHARE = SUPPLY / 4;

    SqueekChain private token;
    SqueekChainHandler private handler;
    address[4] private actors;

    /// @dev The ABI consumed by Foundry's invariant runner, matching StdInvariant.FuzzSelector.
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function setUp() public {
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCA201)];
        token = new SqueekChain();
        assertEq(token.balanceOf(address(this)), SUPPLY, "constructor supply belongs to deployer");
        for (uint256 i = 1; i < actors.length; ++i) {
            assertTrue(token.transfer(actors[i], SHARE), "initial allocation succeeds");
        }
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), SHARE, "each holder starts with a known allocation");
        }
        handler = new SqueekChainHandler(token, actors);
    }

    /// @notice Restricts the stateful fuzzer to the handler, so all transfers are accounted for.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// @notice Only state-changing actions are fuzz targets; ledger getters are excluded.
    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = SqueekChainHandler.transfer.selector;
        selectors[1] = SqueekChainHandler.approve.selector;
        selectors[2] = SqueekChainHandler.transferFrom.selector;
        selectors[3] = SqueekChainHandler.transferTooMuch.selector;
        selectors[4] = SqueekChainHandler.spendTooMuchAllowance.selector;
        selectors[5] = SqueekChainHandler.spendTooMuchBalance.selector;
        selectors[6] = SqueekChainHandler.transferToZero.selector;
        selectors[7] = SqueekChainHandler.approveZeroSpender.selector;
        selectors[8] = SqueekChainHandler.donate.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    function invariant_fixedSupplyEqualsAllTrackedBalances() public view {
        uint256 total = token.balanceOf(address(token));
        for (uint256 i; i < actors.length; ++i) {
            total += token.balanceOf(actors[i]);
        }
        assertEq(token.totalSupply(), SUPPLY, "total supply never changes");
        assertEq(total, SUPPLY, "all balances conserve the original mint");
        assertEq(token.balanceOf(address(0)), 0, "no implicit burns to zero");
        assertEq(token.balanceOf(address(handler)), 0, "handler acquires no tokens");
    }

    function invariant_eachBalanceMatchesAuthorizedInflowsAndOutflows() public view {
        for (uint256 i; i < actors.length; ++i) {
            address holder = actors[i];
            assertEq(
                token.balanceOf(holder) + handler.sent(holder),
                SHARE + handler.received(holder),
                "holder balance reconciles with authorized transfers, including failed and self transfers"
            );
        }
        assertEq(token.balanceOf(address(token)), handler.received(address(token)), "contract donations arrive whole");
    }

    function invariant_allowancesMatchTheLatestApprovalAndSubsequentSpending() public view {
        for (uint256 i; i < actors.length; ++i) {
            address owner = actors[i];
            assertEq(token.allowance(owner, address(0)), 0, "zero spender never acquires approval");
            for (uint256 j; j < actors.length; ++j) {
                address spender = actors[j];
                uint256 approved = handler.approved(owner, spender);
                uint256 remaining = token.allowance(owner, spender);
                if (approved == type(uint256).max) {
                    assertEq(remaining, type(uint256).max, "unlimited approval is never consumed");
                } else {
                    assertEq(
                        remaining + handler.spentSinceApproval(owner, spender),
                        approved,
                        "finite approval equals remaining allowance plus successful spends since the last approval"
                    );
                }
            }
        }
    }

    /// @notice Pins a nonzero path through every handler, independently of random action selection.
    function test_handlerExercisesSuccessFailureRevocationAndAliasing() public {
        handler.approve(0, 1, 10, 2);
        handler.transferFrom(0, 1, 2, 0); // Spend the entire finite allowance.
        assertEq(token.balanceOf(actors[2]), SHARE + 10, "delegated spend reaches a funded recipient");
        assertEq(token.allowance(actors[0], actors[1]), 0, "finite allowance exhausted");

        handler.approve(2, 2, 0, 1); // Unlimited self approval.
        handler.transferFrom(2, 2, 2, 0); // Full-balance self transfer.
        assertEq(token.balanceOf(actors[2]), SHARE + 10, "self transfer preserves balance");
        assertEq(token.allowance(actors[2], actors[2]), type(uint256).max, "unlimited allowance persists");
        handler.approve(2, 2, 0, 0); // Revoke it.
        handler.transferFrom(2, 2, 1, 0); // Zero spend with zero allowance.

        handler.transfer(1, 0, 1);
        handler.transferTooMuch(0, 1, type(uint256).max);
        handler.spendTooMuchAllowance(0, 1, 2, 1);
        handler.spendTooMuchBalance(0, 1, 2, 0, false);
        handler.spendTooMuchBalance(0, 1, 2, type(uint256).max, true);
        handler.transferToZero(0, 1, 1, false);
        handler.transferToZero(0, 1, 1, true);
        handler.approveZeroSpender(0, type(uint256).max);
        handler.donate(3, 1);
        assertEq(token.balanceOf(address(token)), 1, "donated token remains accounted for");

        invariant_fixedSupplyEqualsAllTrackedBalances();
        invariant_eachBalanceMatchesAuthorizedInflowsAndOutflows();
        invariant_allowancesMatchTheLatestApprovalAndSubsequentSpending();
    }
}
