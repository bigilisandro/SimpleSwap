// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC20
 * @dev Interface for the ERC20 standard.
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title ERC20
 * @dev Implementation of the ERC20 standard for LP tokens
 */
contract ERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        address owner = msg.sender;
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        address owner = msg.sender;
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        unchecked {
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }
}

/**
 * @title Math
 * @dev Standard math utilities
 */
library Math {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

/**
 * @title SimpleSwap
 * @author Lisandro Bigi
 * @dev This contract allows users to swap tokens, add/remove liquidity, and query prices.
 * It manages multiple liquidity pools within a single contract and issues LP tokens.
 */
contract SimpleSwap is ERC20 {
    using Math for uint256;

    /// @dev Struct representing a liquidity pool for a token pair
    struct LiquidityPool {
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalLiquidity;
    }

    /// @notice Mapping of token pair hash to liquidity pool data
    mapping(bytes32 => LiquidityPool) public pairPools;

    /// @notice Initializes the LP token as "Pool Share Token" (PST)
    constructor() ERC20("Pool Share Token", "PST") {}

    /**
     * @notice Computes a unique hash for a token pair (order-independent)
     * @param tokenX First token address
     * @param tokenY Second token address
     * @return Hash of the token pair
     */
    function _pairHash(address tokenX, address tokenY)
        internal
        pure
        returns (bytes32)
    {
        (address tMin, address tMax) = tokenX < tokenY
            ? (tokenX, tokenY)
            : (tokenY, tokenX);
        return keccak256(abi.encodePacked(tMin, tMax));
    }

    /**
     * @notice Adds liquidity to the pool and mints LP tokens
     * @param tokenA Address of token A
     * @param tokenB Address of token B
     * @param amountADesired Desired amount of token A to add
     * @param amountBDesired Desired amount of token B to add
     * @param amountAMin Minimum amount of token A to add
     * @param amountBMin Minimum amount of token B to add
     * @param to Address to receive LP tokens
     * @param deadline Unix timestamp after which the transaction is invalid
     * @return amountASent Final amount of token A deposited
     * @return amountBSent Final amount of token B deposited
     * @return liquidity Amount of LP tokens minted
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        public
        returns (
            uint256 amountASent,
            uint256 amountBSent,
            uint256 liquidity
        )
    {
        require(block.timestamp <= deadline, "Transaction expired");

        bytes32 poolId = _pairHash(tokenA, tokenB);
        LiquidityPool storage pool = pairPools[poolId];

        if (pool.totalLiquidity == 0) {
            amountASent = amountADesired;
            amountBSent = amountBDesired;
            liquidity = Math.sqrt(amountASent * amountBSent);
        } else {
            uint256 optimalB = (amountADesired * pool.reserveB) / pool.reserveA;

            if (optimalB <= amountBDesired) {
                require(optimalB >= amountBMin, "Too much slippage on B");
                amountASent = amountADesired;
                amountBSent = optimalB;
            } else {
                uint256 optimalA = (amountBDesired * pool.reserveA) /
                    pool.reserveB;
                require(optimalA >= amountAMin, "Too much slippage on A");
                amountASent = optimalA;
                amountBSent = amountBDesired;
            }

            liquidity = Math.min(
                (amountASent * pool.totalLiquidity) / pool.reserveA,
                (amountBSent * pool.totalLiquidity) / pool.reserveB
            );
        }

        require(liquidity > 0, "Zero liquidity generated");

        IERC20(tokenA).transferFrom(msg.sender, address(this), amountASent);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBSent);

        pool.reserveA += amountASent;
        pool.reserveB += amountBSent;
        pool.totalLiquidity += liquidity;

        _mint(to, liquidity);

        return (amountASent, amountBSent, liquidity);
    }

    /**
     * @notice Removes liquidity from the pool and burns LP tokens
     * @param tokenA Address of token A
     * @param tokenB Address of token B
     * @param liquidity Amount of LP tokens to burn
     * @param amountAMin Minimum amount of token A to receive
     * @param amountBMin Minimum amount of token B to receive
     * @param to Address to receive withdrawn tokens
     * @param deadline Unix timestamp after which the transaction is invalid
     * @return amountASent Amount of token A sent to user
     * @return amountBSent Amount of token B sent to user
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public returns (uint256 amountASent, uint256 amountBSent) {
        require(block.timestamp <= deadline, "Transaction expired");
        require(balanceOf(msg.sender) >= liquidity, "Not enough LP tokens");

        bytes32 poolId = _pairHash(tokenA, tokenB);
        LiquidityPool storage pool = pairPools[poolId];

        amountASent = (liquidity * pool.reserveA) / pool.totalLiquidity;
        amountBSent = (liquidity * pool.reserveB) / pool.totalLiquidity;

        require(amountASent >= amountAMin, "Too much slippage on A");
        require(amountBSent >= amountBMin, "Too much slippage on B");

        pool.reserveA -= amountASent;
        pool.reserveB -= amountBSent;
        pool.totalLiquidity -= liquidity;

        _burn(msg.sender, liquidity);

        IERC20(tokenA).transfer(to, amountASent);
        IERC20(tokenB).transfer(to, amountBSent);

        return (amountASent, amountBSent);
    }

    /**
     * @notice Swaps a fixed amount of tokens for another token in the pair
     * @param amountIn Amount of input token to swap
     * @param amountOutMin Minimum acceptable amount of output tokens
     * @param path Array with input and output token addresses [tokenIn, tokenOut]
     * @param to Address to receive output tokens
     * @param deadline Unix timestamp after which the transaction is invalid
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        require(block.timestamp <= deadline, "Transaction expired");
        require(path.length == 2 && amountIn > 0, "Invalid swap path");

        bytes32 poolId = _pairHash(path[0], path[1]);
        LiquidityPool storage pool = pairPools[poolId];
        require(pool.totalLiquidity > 0, "No liquidity available");

        uint256 reserveIn = pool.reserveA;
        uint256 reserveOut = pool.reserveB;

        uint256 outputAmount = getAmountOut(amountIn, reserveIn, reserveOut);
        require(outputAmount >= amountOutMin, "Output too low");

        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[1]).transfer(to, outputAmount);

        pool.reserveA += amountIn;
        pool.reserveB -= outputAmount;
    }

    /**
     * @notice Returns the current price of tokenB in terms of tokenA
     * @param tokenA Address of base token
     * @param tokenB Address of quote token
     * @return price Quote: how many tokenB per 1 tokenA (scaled by 1e18)
     */
    function getPrice(address tokenA, address tokenB)
        external
        view
        returns (uint256 price)
    {
        bytes32 poolId = _pairHash(tokenA, tokenB);
        LiquidityPool storage pool = pairPools[poolId];
        require(
            pool.reserveA > 0 && pool.reserveB > 0,
            "No liquidity available, its not possible to get a price."
        );

        price = (pool.reserveB * 1e18) / pool.reserveA;
    }

    /**
     * @notice Estimates the output token amount for a given input
     * @param amountIn Amount of input tokens
     * @param reserveIn Input token reserve
     * @param reserveOut Output token reserve
     * @return amountOut Estimated amount of output tokens
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        require(
            amountIn > 0 && reserveIn > 0 && reserveOut > 0,
            "Invalid input, try again."
        );
        amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
    }
} 