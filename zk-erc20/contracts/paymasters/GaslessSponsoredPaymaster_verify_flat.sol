// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Inlined minimal zkSync and OpenZeppelin dependencies for explorer verification.
uint160 constant SYSTEM_CONTRACTS_OFFSET = 0x8000;
address payable constant BOOTLOADER_FORMAL_ADDRESS = payable(address(SYSTEM_CONTRACTS_OFFSET + 0x01));

struct Transaction {
    uint256 txType;
    uint256 from;
    uint256 to;
    uint256 gasLimit;
    uint256 gasPerPubdataByteLimit;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    uint256 paymaster;
    uint256 nonce;
    uint256 value;
    uint256[4] reserved;
    bytes data;
    bytes signature;
    bytes32[] factoryDeps;
    bytes paymasterInput;
    bytes reservedDynamic;
}

enum ExecutionResult {
    Revert,
    Success
}

interface IPaymasterFlow {
    function general(bytes calldata input) external;
    function approvalBased(address _token, uint256 _minAllowance, bytes calldata _innerInput) external;
}

interface IPaymaster {
    function validateAndPayForPaymasterTransaction(
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) external payable returns (bytes4 magic, bytes memory context);

    function postTransaction(
        bytes calldata _context,
        Transaction calldata _transaction,
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        ExecutionResult _txResult,
        uint256 _maxRefundedGas
    ) external payable;
}

bytes4 constant PAYMASTER_VALIDATION_SUCCESS_MAGIC = IPaymaster
    .validateAndPayForPaymasterTransaction
    .selector;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

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
