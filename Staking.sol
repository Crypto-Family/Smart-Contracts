pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract StakingContract is ReentrancyGuard, Ownable {
    IERC20 public token;

    mapping(address => bool) isStaked;
    mapping(address => uint256) public numStakes;
    mapping(address => mapping(uint256 => uint256)) _stakedAmounts;
    mapping(address => mapping(uint256 => uint256)) _stakingTimes;
    mapping(address => mapping(uint256 => uint256)) _lastClaimedTimes;
    uint256 public constant LOCK_TIME = 365 days;

    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
    }

    function stakedAmount(address user, uint256 index)
        external
        view
        returns (uint256)
    {
        return _stakedAmounts[user][index];
    }

    function stakingTimes(address user, uint256 index)
        external
        view
        returns (uint256)
    {
        return _stakingTimes[user][index];
    }

    function lastClaimedTimes(address user, uint256 index)
        external
        view
        returns (uint256)
    {
        return _lastClaimedTimes[user][index];
    }

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, 'Amount must be greater than 0');
        require(token.balanceOf(msg.sender) >= amount, 'Insufficient balance');
        require(
            token.allowance(msg.sender, address(this)) >= amount,
            'Token must be approved first'
        );
        if (!isStaked[msg.sender]) {
            isStaked[msg.sender] = true;
        }

        token.transferFrom(msg.sender, address(this), amount);
        uint256 num = numStakes[msg.sender];
        _stakedAmounts[msg.sender][num] = amount;
        _stakingTimes[msg.sender][num] = block.timestamp;
        _lastClaimedTimes[msg.sender][num] = block.timestamp;
        numStakes[msg.sender]++;
    }

    function claimRewards() external nonReentrant {
        uint256 num = numStakes[msg.sender];
        uint256 rewards = calculateRewards(msg.sender);
        require(rewards > 0, 'No rewards to claim');
        for (uint256 i = 0; i < num; i++) {
            if (
                (block.timestamp >=
                    _lastClaimedTimes[msg.sender][i] + 604800) ||
                (block.timestamp >= _lastClaimedTimes[msg.sender][i] + 1209600)
            ) {
                _lastClaimedTimes[msg.sender][i] = block.timestamp;
            }
        }

        token.transfer(msg.sender, rewards);
    }

    function calculateRewards(address account) public view returns (uint256) {
        uint256 num = numStakes[account];
        uint256 rewards = 0;
        for (uint256 i = 0; i < num; i++) {
            uint256 stakedAmount = _stakedAmounts[account][i];
            uint256 lastClaimedTime = _lastClaimedTimes[account][i];
            uint256 timeElapsed = block.timestamp - lastClaimedTime;
            if (timeElapsed > 0) {
                uint256 rewardPerSecond = (4 * stakedAmount) / (365 days * 100);
                rewards += rewardPerSecond * timeElapsed;
            }
        }
        return rewards;
    }

    function withdraw(uint256 stakeIndex, uint256 amount)
        external
        nonReentrant
    {
        uint256 num = numStakes[msg.sender];
        require(num > stakeIndex, 'Invalid Index');
        require(
            block.timestamp >=
                _stakingTimes[msg.sender][stakeIndex] + LOCK_TIME,
            "Can't withdraw before one year"
        );
        require(
            _stakedAmounts[msg.sender][stakeIndex] >= amount,
            'Withdraw amount should be less than or equal to staked amount'
        );
        uint256 pendingRewards = calculateRewards(msg.sender);
        _stakedAmounts[msg.sender][stakeIndex] -= amount;
        _lastClaimedTimes[msg.sender][stakeIndex] = block.timestamp;
        token.transfer(msg.sender, amount);
        if (_stakedAmounts[msg.sender][stakeIndex] == 0) {
            delete _stakedAmounts[msg.sender][stakeIndex];
            delete _stakingTimes[msg.sender][stakeIndex];
            delete _lastClaimedTimes[msg.sender][stakeIndex];
            numStakes[msg.sender]--;
        }
        if (numStakes[msg.sender] == 0) {
            isStaked[msg.sender] = false;
        }
        if (pendingRewards > 0) {
            token.transfer(msg.sender, pendingRewards);
        }
    }

    function withdrawAll() external nonReentrant {
        uint256 num = numStakes[msg.sender];
        require(
            block.timestamp >= _stakingTimes[msg.sender][0] + LOCK_TIME,
            "Can't withdraw before one year"
        );
        uint256 pendingRewards = calculateRewards(msg.sender);
        uint256 totalAmount = pendingRewards;
        for (uint256 i = 0; i < num; i++) {
            totalAmount += _stakedAmounts[msg.sender][i];
            delete _stakedAmounts[msg.sender][i];
            delete _stakingTimes[msg.sender][i];
            delete _lastClaimedTimes[msg.sender][i];
        }
        numStakes[msg.sender] = 0;
        isStaked[msg.sender] = false;
        token.transfer(msg.sender, totalAmount);
    }

    function emergencyWithdraw() external onlyOwner {
        address owner = owner();
        token.transfer(owner, token.balanceOf(address(this)));
    }
}
