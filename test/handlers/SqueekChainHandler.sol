// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "../support/Test.sol";
import {SqueekChain} from "../../src/SqueekChain.sol";

/// @notice Drives real token calls from four holders and keeps an independent flow ledger.
/// @dev The only destinations are these holders and the token itself, so the invariant can
/// account for every token. No storage writes or balance cheatcodes modify the token.
contract SqueekChainHandler is Test {
    uint256 public constant SUPPLY = 1e27;
    uint256 public constant INITIAL_BALANCE = SUPPLY / 4;

    SqueekChain public immutable token;
    address[4] public actors;

    mapping(address => uint256) public sent;
    mapping(address => uint256) public received;
    mapping(address => mapping(address => uint256)) public approved;
    mapping(address => mapping(address => uint256)) public spentSinceApproval;

    constructor(SqueekChain token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
    }

    /// @notice Transfers zero, one, the full balance or a bounded arbitrary amount; actors may alias.
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(amountSeed, expectedBalance(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "handler transfer must succeed");
        _recordTransfer(from, to, amount);
    }

    /// @notice Replaces or revokes approvals, including the unlimited sentinel and large finite values.
    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        uint256 amount;
        if (mode % 4 == 1) amount = type(uint256).max;
        else if (mode % 4 == 2) amount = bound(amountSeed, 0, SUPPLY);
        else if (mode % 4 == 3) amount = amountSeed;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    /// @notice Spends approvals left by earlier random calls, including self approvals and self transfers.
    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 available = approved[owner][spender];
        if (available != type(uint256).max) available -= spentSinceApproval[owner][spender];
        uint256 balance = expectedBalance(owner);
        uint256 amount = _amount(amountSeed, balance < available ? balance : available);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "handler delegated transfer must succeed");
        spentSinceApproval[owner][spender] += amount;
        _recordTransfer(owner, to, amount);
    }

    /// @notice Exercises failed transfers up to uint256.max without updating the flow ledger.
    function transferTooMuch(uint256 ownerSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance(owner);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(owner);
        token.transfer(to, amount);
    }

    /// @notice A failed delegated spend must neither move balances nor consume an existing approval.
    function spendTooMuchAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 approvalSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 amount = bound(approvalSeed, 0, SUPPLY);
        _approve(owner, spender, amount);

        vm.expectRevert(
            abi.encodeWithSelector(SqueekChain.ERC20InsufficientAllowance.selector, spender, amount, amount + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount + 1);
    }

    /// @notice Approval spending happens before the balance check; its effects must roll back on failure.
    function spendTooMuchBalance(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool unlimited
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance(owner);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max - 1);
        _approve(owner, spender, unlimited ? type(uint256).max : amount);

        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    /// @notice Attempts both direct and delegated transfers to zero, including zero-value transfers.
    function transferToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(amountSeed, expectedBalance(owner));
        if (delegated) _approve(owner, spender, amount);

        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(delegated ? spender : owner);
        if (delegated) token.transferFrom(owner, address(0), amount);
        else token.transfer(address(0), amount);
    }

    /// @notice An invalid approval must leave every previously approved pair untouched.
    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.expectRevert(abi.encodeWithSelector(SqueekChain.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    /// @notice Tokens sent to the token contract still count toward supply; nobody impersonates it.
    function donate(uint256 ownerSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        uint256 amount = _amount(amountSeed, expectedBalance(owner));
        vm.prank(owner);
        assertTrue(token.transfer(address(token), amount), "transfer to a contract must succeed");
        _recordTransfer(owner, address(token), amount);
    }

    /// @notice Expected holder balance from initial allocation and cumulative authorized flows.
    function expectedBalance(address holder) public view returns (uint256) {
        return INITIAL_BALANCE + received[holder] - sent[holder];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "handler approval must succeed");
        approved[owner][spender] = amount;
        spentSinceApproval[owner][spender] = 0;
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        sent[from] += amount;
        received[to] += amount;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function _amount(uint256 seed, uint256 maximum) private pure returns (uint256) {
        if (seed % 4 == 0) return maximum;
        if (seed % 4 == 1) return maximum == 0 ? 0 : 1;
        if (seed % 4 == 2) return 0;
        return bound(seed, 0, maximum);
    }
}
