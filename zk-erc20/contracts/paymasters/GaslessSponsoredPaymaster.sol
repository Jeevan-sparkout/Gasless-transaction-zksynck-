// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    IPaymaster,
    ExecutionResult,
    PAYMASTER_VALIDATION_SUCCESS_MAGIC
} from "@matterlabs/zksync-contracts/contracts/system-contracts/interfaces/IPaymaster.sol";
import {IPaymasterFlow} from "@matterlabs/zksync-contracts/contracts/system-contracts/interfaces/IPaymasterFlow.sol";
import "@matterlabs/zksync-contracts/contracts/system-contracts/libraries/TransactionHelper.sol";
import "@matterlabs/zksync-contracts/contracts/system-contracts/Constants.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Paymaster that sponsors gas for users in general flow.
/// Users can submit transactions even with zero ETH balance, while this
/// contract pays the bootloader from its own ETH balance.
contract GaslessSponsoredPaymaster is IPaymaster, Ownable {
    bool public sponsoringEnabled = true;
    bool public allowAllUsers = true;
    uint256 public maxGasLimitPerTx;
    mapping(address => bool) public sponsoredUsers;

    event SponsoringEnabledSet(bool enabled);
    event AllowAllUsersSet(bool allowAllUsers);
    event UserSponsorshipSet(address indexed user, bool sponsored);
    event MaxGasLimitPerTxSet(uint256 maxGasLimitPerTx);
    event GasSponsored(
        address indexed user,
        uint256 requiredETH,
        uint256 gasLimit,
        uint256 maxFeePerGas
    );

    modifier onlyBootloader() {
        require(
            msg.sender == BOOTLOADER_FORMAL_ADDRESS,
            "Only bootloader can call this method"
        );
        _;
    }

    constructor(
        address initialOwner,
        uint256 _maxGasLimitPerTx
    ) Ownable(initialOwner) {
        maxGasLimitPerTx = _maxGasLimitPerTx;
    }

    function setSponsoringEnabled(bool enabled) external onlyOwner {
        sponsoringEnabled = enabled;
        emit SponsoringEnabledSet(enabled);
    }

    function setAllowAllUsers(bool enabled) external onlyOwner {
        allowAllUsers = enabled;
        emit AllowAllUsersSet(enabled);
    }

    function setUserSponsorship(address user, bool sponsored) external onlyOwner {
        sponsoredUsers[user] = sponsored;
        emit UserSponsorshipSet(user, sponsored);
    }

    function setMaxGasLimitPerTx(uint256 _maxGasLimitPerTx) external onlyOwner {
        maxGasLimitPerTx = _maxGasLimitPerTx;
        emit MaxGasLimitPerTxSet(_maxGasLimitPerTx);
    }

    function validateAndPayForPaymasterTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    )
        external
        payable
        onlyBootloader
        returns (bytes4 magic, bytes memory context)
    {
        require(sponsoringEnabled, "Sponsoring is disabled");
        require(
            _transaction.paymasterInput.length >= 4,
            "The standard paymaster input must be at least 4 bytes long"
        );

        bytes4 paymasterInputSelector = bytes4(_transaction.paymasterInput[0:4]);
        require(
            paymasterInputSelector == IPaymasterFlow.general.selector,
            "Unsupported paymaster flow"
        );

        address user = address(uint160(_transaction.from));
        require(allowAllUsers || sponsoredUsers[user], "User is not sponsored");

        if (maxGasLimitPerTx > 0) {
            require(
                _transaction.gasLimit <= maxGasLimitPerTx,
                "Gas limit exceeds configured maximum"
            );
        }

        // Use max possible fee upper bound for sponsorship.
        uint256 requiredETH = _transaction.gasLimit * _transaction.maxFeePerGas;

        (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{
            value: requiredETH
        }("");
        require(
            success,
            "Failed to transfer tx fee to the bootloader. Paymaster balance might not be enough."
        );

        emit GasSponsored(
            user,
            requiredETH,
            _transaction.gasLimit,
            _transaction.maxFeePerGas
        );

        magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;
        context = "";
    }

    function postTransaction(
        bytes calldata,
        Transaction calldata,
        bytes32,
        bytes32,
        ExecutionResult,
        uint256
    ) external payable override onlyBootloader {}

    function withdraw(address payable to) external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = to.call{value: balance}("");
        require(success, "Failed to withdraw funds from paymaster.");
    }

    receive() external payable {}
}
