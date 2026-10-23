// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "./support/Test.sol";
import {SqueekChain} from "../src/SqueekChain.sol";

/// @notice Success and failure paths of SqueekChain: the fixed mint, ERC-20 transfers and
/// allowances, the absence of any admin entry point, and the runtime-code floor the launch applies.
contract SqueekChainTest is Test {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @dev 1,000,000,000 SQK in minor units (18 decimals).
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);
    address internal constant ATTACKER = address(0xBEEF);

    SqueekChain internal token;

    function setUp() public {
        vm.label(DEPLOYER, "deployer");
        vm.label(ALICE, "alice");
        vm.label(BOB, "bob");
        vm.label(CAROL, "carol");
        vm.label(ATTACKER, "attacker");
        vm.prank(DEPLOYER);
        token = new SqueekChain();
    }

    // ------------------------------------------------------------------
    // Metadata and the one-time mint
    // ------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "SqueekChain", "name");
        assertEq(token.symbol(), "SQK", "symbol");
        assertEq(uint256(token.decimals()), 18, "decimals");
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(SUPPLY, 1e27, "the supply constant is one billion tokens with 18 decimals");
        assertEq(token.TOTAL_SUPPLY(), SUPPLY, "TOTAL_SUPPLY");
        assertEq(token.totalSupply(), SUPPLY, "totalSupply");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "the deployer holds the whole supply");
        assertEq(token.balanceOf(address(this)), 0, "the test contract holds nothing");
        assertEq(token.balanceOf(address(0)), 0, "the zero address holds nothing");
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        SqueekChain fresh = new SqueekChain();
        assertEq(fresh.balanceOf(ALICE), SUPPLY, "a fresh deployment mints to its own deployer");
    }

    // ------------------------------------------------------------------
    // transfer
    // ------------------------------------------------------------------

    function test_transferMovesBalanceAndEmits() public {
        uint256 amount = 1_000 * 10 ** 18;
        vm.expectEmit(true, true, true, true);
        emit Transfer(DEPLOYER, ALICE, amount);
        vm.prank(DEPLOYER);
        bool ok = token.transfer(ALICE, amount);
        assertTrue(ok, "transfer returns true");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount, "sender debited");
        assertEq(token.balanceOf(ALICE), amount, "receiver credited in full");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transferWholeBalanceLeavesZero() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), 0, "sender emptied");
        assertEq(token.balanceOf(ALICE), SUPPLY, "receiver holds everything");
    }

    function test_transferOfZeroSucceeds() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0), "a zero transfer from an empty account succeeds");
        assertEq(token.balanceOf(BOB), 0, "nothing moved");
    }

    function test_selfTransferKeepsBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(DEPLOYER, SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "a self transfer changes nothing");
    }

    function test_transferRevertsWhenBalanceInsufficient() public {
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
    }

    function test_transferRevertsOneAboveBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(SqueekChain.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, SUPPLY + 1)
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY + 1);
    }

    function test_transferRevertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(DEPLOYER);
        token.transfer(address(0), 1);
    }

    // ------------------------------------------------------------------
    // approve / allowance / transferFrom
    // ------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(DEPLOYER, ALICE, 123);
        vm.prank(DEPLOYER);
        assertTrue(token.approve(ALICE, 123), "approve returns true");
        assertEq(token.allowance(DEPLOYER, ALICE), 123, "allowance set");
        assertEq(token.allowance(ALICE, DEPLOYER), 0, "the reverse allowance is untouched");
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(DEPLOYER);
        token.approve(ALICE, 500);
        token.approve(ALICE, 7);
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, ALICE), 7, "the last approval wins");
    }

    function test_approveRevertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InvalidSpender.selector, address(0)));
        vm.prank(DEPLOYER);
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowanceAndEmits() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 100);

        vm.expectEmit(true, true, true, true);
        emit Transfer(DEPLOYER, BOB, 60);
        vm.prank(ALICE);
        bool ok = token.transferFrom(DEPLOYER, BOB, 60);

        assertTrue(ok, "transferFrom returns true");
        assertEq(token.balanceOf(BOB), 60, "receiver credited");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 60, "owner debited");
        assertEq(token.balanceOf(ALICE), 0, "the spender holds nothing itself");
        assertEq(token.allowance(DEPLOYER, ALICE), 40, "allowance reduced by what was spent");
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1);
    }

    function test_transferFromRevertsWhenAllowanceTooSmall() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 10);
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InsufficientAllowance.selector, ALICE, 10, 11));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 11);
        assertEq(token.allowance(DEPLOYER, ALICE), 10, "a failed spend leaves the allowance");
        assertEq(token.balanceOf(BOB), 0, "a failed spend moves nothing");
    }

    function test_transferFromRevertsWhenOwnerBalanceInsufficient() public {
        vm.prank(ALICE);
        token.approve(BOB, 10);
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InsufficientBalance.selector, ALICE, 0, 5));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 5);
        assertEq(token.allowance(ALICE, BOB), 10, "a reverted transferFrom does not consume allowance");
    }

    function test_transferFromRevertsToZeroAddress() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, 10);
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, address(0), 1);
    }

    function test_unlimitedAllowanceIsNotDecreased() public {
        vm.prank(DEPLOYER);
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(DEPLOYER, BOB, 1_000);
        assertEq(token.allowance(DEPLOYER, ALICE), type(uint256).max, "an unlimited allowance stays unlimited");
        assertEq(token.balanceOf(BOB), 1_000, "receiver credited");
    }

    function test_holderCannotBeMovedByDeployerWithoutApproval() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1_000);
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(ALICE, DEPLOYER, 1);
        assertEq(token.balanceOf(ALICE), 1_000, "the deployer has no power over a holder");
    }

    // ------------------------------------------------------------------
    // No admin surface: nothing mints, pauses, freezes or seizes
    // ------------------------------------------------------------------

    function test_noCallIncreasesSupplyOrMintsToCaller() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ATTACKER, type(uint128).max);
            vm.prank(ATTACKER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, string.concat("an unknown selector must revert: ", signatures[i]));
            vm.prank(DEPLOYER);
            (ok,) = address(token).call(data);
            assertFalse(ok, string.concat("the deployer has no admin call: ", signatures[i]));
        }
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
        assertEq(token.balanceOf(ATTACKER), 0, "nothing minted to the attacker");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "the deployer still holds exactly the mint");
    }

    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        uint256 held = SUPPLY / 1_000;
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, true);
            vm.prank(DEPLOYER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, string.concat("no such privileged call: ", signatures[i]));
        }
        assertEq(token.balanceOf(ALICE), held, "the holder still holds what it held");
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, held / 2), "the holder can still transfer");
        assertEq(token.balanceOf(BOB), held / 2, "the holder's transfer delivered in full");
    }

    function test_rejectsPlainEther() public {
        (bool ok,) = address(token).call{value: 1}("");
        assertFalse(ok, "the token has no receive or fallback");
        assertEq(address(token).balance, 0, "the token holds no ether");
    }

    /// @dev The launch floor's reachability scan: from the start or a JUMPDEST to a terminating
    /// opcode, no DELEGATECALL, CALLCODE or SELFDESTRUCT. PUSH data is skipped, not decoded.
    function test_runtimeCodeHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0, "the token has runtime code");
        assertLe(runtime.length, 24_576, "runtime within EIP-170");
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
                assertTrue(op != 0xF2, "runtime code contains CALLCODE");
                assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ------------------------------------------------------------------
    // Fuzz: conservation and bounds
    // ------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = amount % (SUPPLY + 1);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(to, amount), "transfer returns true");
        if (to == DEPLOYER) {
            assertEq(token.balanceOf(DEPLOYER), SUPPLY, "self transfer conserves the balance");
        } else {
            assertEq(token.balanceOf(to), amount, "receiver credited exactly");
            assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount, "sender debited exactly");
            assertEq(token.balanceOf(to) + token.balanceOf(DEPLOYER), SUPPLY, "balances sum to the supply");
        }
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function testFuzz_transferRevertsAboveBalance(uint256 excess) public {
        excess = 1 + (excess % (type(uint256).max - SUPPLY));
        uint256 amount = SUPPLY + excess;
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, amount));
        vm.prank(DEPLOYER);
        token.transfer(ALICE, amount);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowed, uint256 spend) public {
        allowed = allowed % SUPPLY;
        spend = spend % SUPPLY;
        vm.prank(DEPLOYER);
        token.approve(ALICE, allowed);
        if (spend > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(SqueekChain.ERC20InsufficientAllowance.selector, ALICE, allowed, spend)
            );
            vm.prank(ALICE);
            token.transferFrom(DEPLOYER, BOB, spend);
            assertEq(token.balanceOf(BOB), 0, "nothing moved");
            assertEq(token.allowance(DEPLOYER, ALICE), allowed, "allowance untouched");
        } else {
            vm.prank(ALICE);
            assertTrue(token.transferFrom(DEPLOYER, BOB, spend), "transferFrom returns true");
            assertEq(token.balanceOf(BOB), spend, "receiver credited exactly");
            assertEq(token.balanceOf(DEPLOYER), SUPPLY - spend, "owner debited exactly");
            assertEq(token.allowance(DEPLOYER, ALICE), allowed - spend, "allowance reduced exactly");
        }
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function testFuzz_approveAnyAmount(address spender, uint256 amount) public {
        vm.assume(spender != address(0));
        vm.prank(ALICE);
        assertTrue(token.approve(spender, amount), "approve returns true");
        assertEq(token.allowance(ALICE, spender), amount, "allowance recorded exactly");
    }
}
