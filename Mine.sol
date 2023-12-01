// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "./interfaces/ICard.sol";

contract Mine is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC1155HolderUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant OPERATOR = keccak256("OPERATOR");

    CountersUpgradeable.Counter private _currentId;

    address public rewardToken;

    ICard public card;

    address public payee;

    uint256 public rewardPerSecond;
    uint256 public rewardPerHashrateStored;
    uint256 public totalHashrates;
    uint256 public lastUpdateTime;
    uint256 public withdrawAuditLimit;

    UserWithdraw[] public userWithdraws;

    struct UserWithdraw {
        uint256 id;
        address account;
        uint256 amount;
        uint256 withdrawAuditLimit;
    }

    struct User {
        uint256 hashrate;
        uint256 reward;
        uint256 claimReward;
        uint256 lastRewardPerHashrate;
        uint256 lastRewardTime;
        uint256 lastWithdrawTime;
        uint256 lastStakeTime;
    }

    mapping(address => mapping(uint256 => uint256)) public userStakeCards;
    mapping(address => User) public users;
    mapping(uint256 => uint256) public cardHashRate;
    mapping(uint256 => uint256) public withdrawIndexedById;

    event Staked(address indexed account, uint256[] ids, uint256[] amounts);
    event Unstaked(address indexed account, uint256[] ids, uint256[] amounts);
    event Claimed(address indexed account, uint256 amount,uint256 withdrawAuditLimit);
    event Withdrawn(address indexed account,uint256 id,bool pass,uint256 amount);
    event PayeeUpdated(address indexed oldVal, address indexed newVal);
    event WithdrawnUpdated(uint256 oldVal, uint256 newVal);

    function initialize(
        address _rewardToken,
        address _card,
        address _payee
    ) public initializer {
        rewardToken = _rewardToken;
        card = ICard(_card);
        payee = _payee;

        cardHashRate[card.SATELLITE()] = 1;
        cardHashRate[card.PLANET()] = 8;
        cardHashRate[card.STAR()] = 32;

        rewardPerSecond = 63425925925925930;

        withdrawAuditLimit = 1e18;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR, _msgSender());
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(AccessControlUpgradeable, ERC1155ReceiverUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    modifier updateReward(address account) {
        rewardPerHashrateStored = rewardPerHashrate();
        lastUpdateTime = block.timestamp;
        if (account != address(0)) {
            User storage user = users[account];
            user.reward = earned(account);
            user.lastRewardPerHashrate = rewardPerHashrateStored;
            user.lastRewardTime = lastUpdateTime;
        }
        _;
    }

    function setPayee(address payable newPayee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit PayeeUpdated(payee, newPayee);
        payee = newPayee;
    }

    function setWithdrawAuditLimit(uint256 _withdrawAuditLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit WithdrawnUpdated(withdrawAuditLimit, _withdrawAuditLimit);
        withdrawAuditLimit = _withdrawAuditLimit;
    }

    function getWithdrawList(uint256 page, uint256 pageSize)
        external
        view
        returns (uint256 length,UserWithdraw[] memory)
    {
        length = userWithdraws.length;
        uint256 startIndex = (page - 1) * pageSize;
        uint256 endIndex = startIndex + pageSize;
        if (endIndex > length) {
            endIndex = length;
        }
        UserWithdraw[] memory list = new UserWithdraw[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            list[i - startIndex] = userWithdraws[i];
        }
        return (length,list);
    }

    function rewardPerHashrate() public view returns (uint256) {
        if (totalHashrates == 0) {
            return rewardPerHashrateStored;
        }
        return
            rewardPerHashrateStored +
            (((block.timestamp - lastUpdateTime) * rewardPerSecond * 1e18) /
                totalHashrates);
    }

    function earned(address account) public view returns (uint256) {
        User memory user = users[account];

        uint256 reward = user.reward +
            ((user.hashrate *
                (rewardPerHashrate() - user.lastRewardPerHashrate)) / 1e18);

        return reward;
    }

    function stake(
        uint256[] memory ids,
        uint256[] memory amounts
    ) external nonReentrant updateReward(msg.sender) {
        require(ids.length == amounts.length, "length error");
        
        uint256 hashRate = 0;
        for (uint256 i = 0; i < ids.length; i++) {
            require(ids[i] == card.SATELLITE() || ids[i] == card.PLANET() || ids[i] == card.STAR(), "card id error");
            require(amounts[i] > 0, "amount error");

            userStakeCards[msg.sender][ids[i]] += amounts[i];
            hashRate += amounts[i] * cardHashRate[ids[i]];
        }

        User storage user = users[msg.sender];
        user.lastRewardTime = user.hashrate == 0?block.timestamp:user.lastRewardTime;
        user.hashrate += hashRate;
        user.lastStakeTime = block.timestamp;
        
        totalHashrates += hashRate;

        IERC1155Upgradeable(card).safeBatchTransferFrom(
            msg.sender,
            address(this),
            ids,
            amounts,
            ""
        );

        emit Staked(msg.sender, ids, amounts);
    }

    function unstake(
        uint256[] memory ids,
        uint256[] memory amounts
    ) external nonReentrant updateReward(msg.sender) {
        require(ids.length == amounts.length, "length error");
        uint256 hashRate = 0;
        for (uint256 i = 0; i < ids.length; i++) {
            require(ids[i] == card.SATELLITE() || ids[i] == card.PLANET() || ids[i] == card.STAR(), "card id error");
            require(amounts[i] > 0, "amount error");
            require(
                userStakeCards[msg.sender][ids[i]] >= amounts[i],
                "amount error"
            );
            userStakeCards[msg.sender][ids[i]] -= amounts[i];
            hashRate += amounts[i] * cardHashRate[ids[i]];
        }

        User storage user = users[msg.sender];
        user.hashrate -= hashRate;
        totalHashrates -= hashRate;

        IERC1155Upgradeable(card).safeBatchTransferFrom(
            address(this),
            msg.sender,
            ids,
            amounts,
            ""
        );

        emit Unstaked(msg.sender, ids, amounts);
    }

    function claim() external nonReentrant updateReward(msg.sender) {
        User storage user = users[msg.sender];
        require(user.reward > 0, "no reward");

        uint256 reward = user.reward;
        user.reward = 0;
        user.lastWithdrawTime = block.timestamp;
        user.claimReward += reward;
        if(reward <= withdrawAuditLimit){
            IERC20Upgradeable(rewardToken).safeTransfer(msg.sender, reward);
        }else{
            CountersUpgradeable.increment(_currentId);
            UserWithdraw memory userWithdraw;
            userWithdraw.id = CountersUpgradeable.current(_currentId);
            userWithdraw.account = msg.sender;
            userWithdraw.amount = reward;
            userWithdraw.withdrawAuditLimit = withdrawAuditLimit;

            userWithdraws.push(userWithdraw);
            withdrawIndexedById[userWithdraw.id] = userWithdraws.length;
        }

        emit Claimed(msg.sender, reward,withdrawAuditLimit);
    }

    function auditWithdraw(uint256 id, bool pass) external onlyRole(OPERATOR){
        uint256 index = withdrawIndexedById[id];
        require(index > 0, "id error");

        UserWithdraw storage userWithdraw = userWithdraws[index - 1];
        require(userWithdraw.amount > 0, "withdraw amount error");
        require(userWithdraw.account != address(0), "withdraw account error");

        if (pass) {
            IERC20Upgradeable(rewardToken).safeTransfer(
                userWithdraw.account,
                userWithdraw.amount
            );
        } else {
            User storage user = users[userWithdraw.account];
            user.reward += userWithdraw.amount;
        }

        if (userWithdraws.length > 1) {
            userWithdraws[index - 1] = userWithdraws[userWithdraws.length - 1];
            withdrawIndexedById[userWithdraws[index - 1].id] = index;
        }

        userWithdraws.pop();
        delete withdrawIndexedById[id];

        emit Withdrawn(userWithdraw.account,id,pass,userWithdraw.amount);
    }
}
