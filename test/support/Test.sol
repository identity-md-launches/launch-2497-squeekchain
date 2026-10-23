// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The subset of Foundry's cheatcode interface these tests use. Signatures are the ones
/// forge dispatches on (they match forge-std's `Vm.sol`); the cheatcodes live in forge itself, so
/// no library has to be vendored for the tests to run.
interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address msgSender) external;
    function startPrank(address msgSender) external;
    function stopPrank() external;
    function expectRevert() external;
    function expectRevert(bytes calldata revertData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData, address emitter) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory logs);
    function assume(bool condition) external pure;
    function label(address account, string calldata newLabel) external;
    function assertTrue(bool condition, string calldata err) external pure;
    function assertFalse(bool condition, string calldata err) external pure;
    function assertEq(bool left, bool right, string calldata err) external pure;
    function assertEq(uint256 left, uint256 right, string calldata err) external pure;
    function assertEq(address left, address right, string calldata err) external pure;
    function assertEq(string calldata left, string calldata right, string calldata err) external pure;
    function assertGt(uint256 left, uint256 right, string calldata err) external pure;
    function assertLe(uint256 left, uint256 right, string calldata err) external pure;
}

/// @notice A minimal test base: the cheatcode handle and assertion wrappers. Assertions are
/// forge's own cheatcodes, so a failure is reported with both values like forge-std's.
abstract contract Test {
    address internal constant VM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
    Vm internal constant vm = Vm(VM_ADDRESS);

    /// @dev Maps arbitrary fuzz inputs into an inclusive range without discarding cases.
    /// Preserves inputs already in range, including both endpoints and the full uint256 domain.
    function bound(uint256 value, uint256 minimum, uint256 maximum) internal pure returns (uint256) {
        require(minimum <= maximum, "invalid bounds");
        if (value >= minimum && value <= maximum) return value;
        return minimum + value % (maximum - minimum + 1);
    }

    function assertTrue(bool condition, string memory err) internal pure {
        vm.assertTrue(condition, err);
    }

    function assertFalse(bool condition, string memory err) internal pure {
        vm.assertFalse(condition, err);
    }

    function assertEq(bool left, bool right, string memory err) internal pure {
        vm.assertEq(left, right, err);
    }

    function assertEq(uint256 left, uint256 right, string memory err) internal pure {
        vm.assertEq(left, right, err);
    }

    function assertEq(address left, address right, string memory err) internal pure {
        vm.assertEq(left, right, err);
    }

    function assertEq(string memory left, string memory right, string memory err) internal pure {
        vm.assertEq(left, right, err);
    }

    function assertGt(uint256 left, uint256 right, string memory err) internal pure {
        vm.assertGt(left, right, err);
    }

    function assertLe(uint256 left, uint256 right, string memory err) internal pure {
        vm.assertLe(left, right, err);
    }
}
