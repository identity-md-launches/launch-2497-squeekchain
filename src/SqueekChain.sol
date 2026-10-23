// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title SqueekChain (SQK)
/// @notice A fixed-supply ERC-20 token. The whole supply of 1,000,000,000 SQK (18 decimals) is
/// minted once, in the constructor, to the deployer (`msg.sender`). There is no owner, no mint
/// function, no burn function, no pause, no blocklist and no fee on transfer: after deployment
/// nothing can change the supply or move a balance other than its holder or an approved spender.
/// @dev Self-contained on purpose: the launch deploys the creation code as built, so the contract
/// imports nothing. Behaviour and error names follow OpenZeppelin's ERC20 v5 so integrators see
/// the custom errors they already expect.
contract SqueekChain {
    /// @notice ERC-20 token name.
    string private constant NAME = "SqueekChain";
    /// @notice ERC-20 token symbol.
    string private constant SYMBOL = "SQK";
    /// @notice ERC-20 decimals.
    uint8 private constant DECIMALS = 18;
    /// @notice The entire, fixed supply in minor units: 1,000,000,000 * 10^18.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    mapping(address account => uint256) private _balances;
    mapping(address account => mapping(address spender => uint256)) private _allowances;

    /// @notice Emitted when `value` tokens move from `from` to `to`. The mint emits it from the zero address.
    event Transfer(address indexed from, address indexed to, uint256 value);
    /// @notice Emitted when `owner` sets the allowance of `spender` to `value`.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @dev `sender` holds `balance` but `needed` was asked for.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    /// @dev The zero address cannot send.
    error ERC20InvalidSender(address sender);
    /// @dev The zero address cannot receive.
    error ERC20InvalidReceiver(address receiver);
    /// @dev `spender` may spend `allowance` but `needed` was asked for.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    /// @dev The zero address cannot approve.
    error ERC20InvalidApprover(address approver);
    /// @dev The zero address cannot be approved.
    error ERC20InvalidSpender(address spender);

    /// @notice Mints the whole supply to the deployer, once. At launch the deployer is the factory,
    /// which pays the supply out (swarm share, pool seed, remainder) after this returns.
    constructor() {
        _balances[msg.sender] = TOTAL_SUPPLY;
        emit Transfer(address(0), msg.sender, TOTAL_SUPPLY);
    }

    /// @notice The token name.
    function name() external pure returns (string memory) {
        return NAME;
    }

    /// @notice The token symbol.
    function symbol() external pure returns (string memory) {
        return SYMBOL;
    }

    /// @notice The number of decimals the token uses.
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @notice The total supply. It never changes after the constructor.
    function totalSupply() external pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    /// @notice The balance of `account`.
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @notice The remaining amount `spender` may transfer on behalf of `owner`.
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @notice Moves `value` tokens from the caller to `to`.
    /// @dev Reverts with `ERC20InvalidReceiver` for the zero address and `ERC20InsufficientBalance`
    /// when the caller holds less than `value`. Always returns true otherwise.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Sets the allowance of `spender` over the caller's tokens to `value`.
    /// @dev Reverts with `ERC20InvalidSpender` for the zero address. Always returns true otherwise.
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value, true);
        return true;
    }

    /// @notice Moves `value` tokens from `from` to `to` using the caller's allowance.
    /// @dev Reverts with `ERC20InsufficientAllowance` when the allowance is below `value`. An
    /// allowance of `type(uint256).max` is treated as unlimited and is not decreased.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) revert ERC20InsufficientBalance(from, fromBalance, value);
        unchecked {
            // fromBalance >= value was checked above.
            _balances[from] = fromBalance - value;
            // The sum of all balances is TOTAL_SUPPLY, so no balance can exceed it.
            _balances[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent) private {
        if (owner == address(0)) revert ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        _allowances[owner][spender] = value;
        if (emitEvent) emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) private {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance == type(uint256).max) return;
        if (currentAllowance < value) revert ERC20InsufficientAllowance(spender, currentAllowance, value);
        unchecked {
            _approve(owner, spender, currentAllowance - value, false);
        }
    }
}
