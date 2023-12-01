// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./interfaces/ICard.sol";
import "./interfaces/IPool.sol";

contract PoolV2 is AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant OPERATOR = keccak256("OPERATOR");
    IERC20Upgradeable public token;
    ICard public card;
    IPool public pool;

    struct User {
        address superior;
        uint256 stakingTotal;
    }

    struct CardInfo {
        uint256 supply;
        uint256 price;
    }

    mapping(address => User) private _users;

    mapping(uint256 => CardInfo) public cards;
    mapping(uint256 => uint256) public totalSupply;
    mapping(uint256 => bool) public periods;

    uint256 public minStaking;
    uint256 public maxStaking;
    uint256 private _totalStaking;

    address public payee;

    event Deposit(
        address indexed user,
        uint256 amount,
        uint256 indexed period,
        uint256 nftId,
        uint8 renewal
    );

    event BindSuperior(address indexed user, address indexed superior);
    event MinStakingUpdated(uint256 oldVal, uint256 newVal);
    event MaxStakingUpdated(uint256 oldVal, uint256 newVal);
    event PayeeUpdated(address indexed oldVal, address indexed newVal);
    event MaxCardTotalUpdated(uint256 oldVal, uint256 newVal);
    event PeriodUpdated(uint256 period, bool oldVal, bool newVal);

    modifier onlyOperator() {
        require(hasRole(OPERATOR, _msgSender()), "Not an operator");
        _;
    }

    function initialize(
        address token_,
        address card_,
        address pool_,
        address payee_
    ) public initializer {
        __AccessControl_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR, _msgSender());

        token = IERC20Upgradeable(token_);
        card = ICard(card_);
        pool = IPool(pool_);
        payee = payee_;

        minStaking = 150 ether;
        maxStaking = 1000000 ether;

        totalSupply[card.SATELLITE()] = 2000;
        totalSupply[card.PLANET()] = 200;
        totalSupply[card.STAR()] = 50;

        cards[card.SATELLITE()].price = 1500 ether;
        cards[card.PLANET()].price = 10000 ether;
        cards[card.STAR()].price = 40000 ether;

        periods[7] = true;
        periods[30] = true;
        periods[90] = true;
        periods[360] = true;
    }

    function setPayee(address payable newPayee) external onlyOperator {
        emit PayeeUpdated(payee, newPayee);
        payee = newPayee;
    }

    function setMinStaking(uint256 v) external onlyOperator {
        emit MinStakingUpdated(minStaking, v);
        minStaking = v;
    }

    function setMaxStaking(uint256 v) external onlyOperator {
        emit MaxStakingUpdated(maxStaking, v);
        maxStaking = v;
    }

    function setTotalSupply(uint256 cardId, uint256 v) external onlyOperator {
        emit MaxCardTotalUpdated(totalSupply[cardId], v);
        totalSupply[cardId] = v;
    }

    function setPeriod(uint256 period, bool v) external onlyOperator {
        emit PeriodUpdated(period, periods[period], v);
        periods[period] = v;
    }

    function users(address account) public view returns (address, uint256) {
        (, uint256 amount) = pool.users(account);
        uint256 stakingAmount = _users[account].stakingTotal + amount;
        return (_users[account].superior, stakingAmount);
    }

    function totalStaking() external view returns (uint256) {
        uint256 stakingAmount = _totalStaking + pool.totalStaking();
        return stakingAmount;
    }

    function bindSuperior(address superior) external nonReentrant {
        require(superior != address(0), " Superior is zero address");
        require(superior != _msgSender(), " Superior is self");
        require(
            _users[_msgSender()].superior == address(0),
            " Superior already bound"
        );

        _users[_msgSender()].superior = superior;
        emit BindSuperior(_msgSender(), superior);
    }

    function depositToken(
        uint256 amount,
        uint256 period,
        uint8 renewal
    ) external nonReentrant {
        _checkUserDeposit(amount, period, renewal);
        token.safeTransferFrom(_msgSender(), payee, amount);
        _deposit(amount, period, 0, renewal);
    }

    function depositNft(
        uint256 id,
        uint256 amount,
        uint8 renewal
    ) external nonReentrant {
        require(amount >= 1, "card amount is error");

        require(
            cards[id].supply + amount <= totalSupply[id],
            "card totalSupply is error"
        );

        uint256 price = amount * cards[id].price;

        uint256 period = 90;
        
        _checkUserDeposit(price, period, renewal);
        
        cards[id].supply += amount;
        token.safeTransferFrom(_msgSender(), payee, price);

        card.mint(msg.sender, id, amount, "");

        _deposit(price, period, id, renewal);
    }

    function _deposit(
        uint256 amount,
        uint256 period,
        uint256 nftId,
        uint8 renewal
    ) internal {
        _totalStaking += amount;
        _users[_msgSender()].stakingTotal += amount;
        
        emit Deposit(_msgSender(), amount, period, nftId, renewal);
    }

    function _checkUserDeposit(
        uint256 amount,
        uint256 period,
        uint8 renewal
    ) private view {
        require(periods[period], "UsdtStakingPool: Incorrect depositType");
        require(
            amount >= minStaking && amount <= maxStaking,
            "UsdtStakingPool: Incorrect amount"
        );
        (, uint256 stakingAmount) = users(_msgSender());
        require(
            stakingAmount + amount <= maxStaking,
            "UsdtStakingPool: Incorrect amount"
        );
        require(renewal <= 1, "UsdtStakingPool: Incorrect renewal");
    }
}
