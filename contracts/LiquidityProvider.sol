// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import '../node_modules/@openzeppelin/contracts/access/AccessControl.sol';
import '../node_modules/@openzeppelin/contracts/math/SafeMath.sol';
import '../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../node_modules/@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '../node_modules/@openzeppelin/contracts/utils/Address.sol';

contract LiquidityProvider is AccessControl {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");             // 0xe2f4eaae4a9751e85a3e4a7b9587827a877f29914755229b07a7b2da98285f70
    
    address public admin;
    address public newAdmin;
    uint256 public changeAdminCalledAt;
    uint256 public constant timelockDuration = 2 minutes;

    // user => token => amount
    mapping(address => mapping(address => uint256)) public userDeposits;
    
    constructor(address _admin, address[] memory _signers) public {
        admin = _admin;
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setRoleAdmin(SIGNER_ROLE, DEFAULT_ADMIN_ROLE);
        
        for(uint256 i=0; i<_signers.length; i++) {
            _setupRole(SIGNER_ROLE, _signers[i]);
        }
    }
    
    modifier onlySigner() {
        require(hasRole(SIGNER_ROLE, msg.sender), "Must be Signer");
        _;
    }
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Must be Admin");
        _;
    }
    
    function addLiquidity (
        address _tokenAddress, 
        uint256 _amount
    ) external payable {
        if(_tokenAddress != ETH) {
            require(msg.value == 0, "ETH sent with token");
            IERC20(_tokenAddress).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
            userDeposits[msg.sender][_tokenAddress] = _amount;
        } else {
            userDeposits[msg.sender][_tokenAddress] = msg.value;            
        }

    }
    
    function transferFunds (
        address _tokenAddress, 
        uint256 _amount,
        address payable _to
    ) external onlySigner {
        if(_tokenAddress == ETH) {
            require(address(this).balance >= _amount, "Insufficient ETH Balance");
            Address.sendValue(
                _to,
                _amount
            );
        } else {
            require(IERC20(_tokenAddress).balanceOf(address(this)) >= _amount, "Insufficient Token Balance");
            IERC20(_tokenAddress).safeTransfer(
                _to,
                _amount
            );
        }
    }
    
    function addSigner (
        address[] calldata _signers
    ) external {
        for(uint256 i=0; i<_signers.length; i++) {
            // can only be called by admin
            grantRole(SIGNER_ROLE, _signers[i]);
        }
    }
    
    function removeSigner (
        address[] calldata _signers
    ) external {
        for(uint256 i=0; i<_signers.length; i++) {
            // can only be called by admin
            revokeRole(SIGNER_ROLE, _signers[i]);
        }
    }
    
    function changeAdmin (
        address _newAdmin
    ) external onlyAdmin {
        require(msg.sender == admin, "Must be Current Admin");
        
        newAdmin = _newAdmin;
        changeAdminCalledAt = now;
    }
    
    function updateAdmin () external {
        require(newAdmin != address(0), "newAdmin not defined");
        require(now >= changeAdminCalledAt.add(timelockDuration), "Under TimeLock");
        require(msg.sender == newAdmin, "Caller must be New Admin");

        _setupRole (
            DEFAULT_ADMIN_ROLE,
            newAdmin
        );
        
        revokeRole (
            DEFAULT_ADMIN_ROLE,
            admin
        );
        
        admin = newAdmin;
        newAdmin = address(0);
        changeAdminCalledAt = 0;
    }
    
    function timeLockLeft() external view returns(uint256) {
        if(now >= changeAdminCalledAt.add(timelockDuration)) {
            return 0;
        } else {
            return changeAdminCalledAt.add(timelockDuration).sub(now);
        }
    }
}