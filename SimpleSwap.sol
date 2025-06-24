pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);      
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/**
 * @title SimpleSwap
 * @author Lisandro Bigi
 * @dev This contract allows users to swap tokens, add/remove liquidity, and query prices.
 * It manages multiple liquidity pools within a single contract.
 */
contract SimpleSwap is ERC20 {
    /// @dev Struct representing a liquidity pool for a token pair
    struct LiquidityPool {
        uint256 reserveA;
        uint256 reserveB;
        uint256 totalLiquidity;
    }

    /// @notice Mapping of token pair hash to liquidity pool data
    mapping(bytes32 => LiquidityPool) public pairPools;

    /**
     * @notice Computes a unique hash for a token pair (order-independent)
     */
    function _pairHash(address tokenX, address tokenY) internal pure returns (bytes32) {
        (address tMin, address tMax) = tokenX < tokenY ? (tokenX, tokenY) : (tokenY, tokenX);
        return keccak256(abi.encodePacked(tMin, tMax));
    }

    /**
     * @notice Adds liquidity to the pool and mints LP tokens
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
    ) public returns (uint256 amountASent, uint256 amountBSent, uint256 liquidity) {
        require(block.timestamp <= deadline, "Transaction expired");

        bytes32 poolId = _pairHash(tokenA, tokenB);
        LiquidityPool storage pool = pairPools[poolId];

        if (pool.totalLiquidity == 0) {
            // First liquidity provision
            amountASent = amountADesired;
            amountBSent = amountBDesired;
            liquidity = sqrt(amountASent * amountBSent);
        } else {
            // Calculate optimal amounts based on current reserves
            uint256 optimalB = (amountADesired * pool.reserveB) / pool.reserveA;

            if (optimalB <= amountBDesired) {
                require(optimalB >= amountBMin, "Too much slippage on B");
                amountASent = amountADesired;
                amountBSent = optimalB;
            } else {
                uint256 optimalA = (amountBDesired * pool.reserveA) / pool.reserveB;
                require(optimalA >= amountAMin, "Too much slippage on A");
                amountASent = optimalA;
                amountBSent = amountBDesired;
            }

            liquidity = min(
                (amountASent * pool.totalLiquidity) / pool.reserveA,
                (amountBSent * pool.totalLiquidity) / pool.reserveB
            );
        }

        require(liquidity > 0, "Zero liquidity generated");

        // Transfer tokens from user to contract
        IERC20(tokenA).transferFrom(msg.sender, address(this), amountASent);
        IERC20(tokenB).transferFrom(msg.sender, address(this), amountBSent);

        // Update pool reserves
        pool.reserveA += amountASent;
        pool.reserveB += amountBSent;
        pool.totalLiquidity += liquidity;

        // Mint LP tokens
        _mint(to, liquidity);

        return (amountASent, amountBSent, liquidity);
    }

    /**
     * @notice Removes liquidity from a pool.
     * @dev Burns liquidity tokens from the user and sends back the corresponding underlying tokens.
     * @param tokenA The address of one of the tokens in the pair.
     * @param tokenB The address of the other token in the pair.
     * @param liquidity The amount of liquidity tokens to burn.
     * @param amountAMin The minimum amount of tokenA to receive.
     * @param amountBMin The minimum amount of tokenB to receive.
     * @param to The address that will receive the tokens.
     * @param deadline The time after which the transaction will be reverted.
     * @return amountA The actual amount of tokenA received.
     * @return amountB The actual amount of tokenB received.
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

        // Calculate amounts to return
        amountASent = (liquidity * pool.reserveA) / pool.totalLiquidity;
        amountBSent = (liquidity * pool.reserveB) / pool.totalLiquidity;

        require(amountASent >= amountAMin, "Too much slippage on A");
        require(amountBSent >= amountBMin, "Too much slippage on B");

        // Update pool reserves
        pool.reserveA -= amountASent;
        pool.reserveB -= amountBSent;
        pool.totalLiquidity -= liquidity;

        // Burn LP tokens
        _burn(msg.sender, liquidity);

        // Transfer tokens to user
        IERC20(tokenA).transfer(to, amountASent);
        IERC20(tokenB).transfer(to, amountBSent);

        return (amountASent, amountBSent);
    }

    /**
     * @notice Swaps an exact amount of input tokens for as many output tokens as possible.
     * @dev The path must be a direct swap (length of 2).
     * @param amountIn The amount of input tokens to send.
     * @param amountOutMin The minimum amount of output tokens to receive.
     * @param path An array of token addresses, representing the swap path. Must have a length of 2.
     * @param to The address that will receive the output tokens.
     * @param deadline The time after which the transaction will be reverted.
     * @return amounts An array containing the input and output amounts.
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

        // Determine which token is which in the pool
        (uint256 reserveIn, uint256 reserveOut) = _getReserves(pool, path[0], path[1]);

        uint256 outputAmount = getAmountOut(amountIn, reserveIn, reserveOut);
        require(outputAmount >= amountOutMin, "Output too low");

        // Transfer tokens
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        IERC20(path[1]).transfer(to, outputAmount);

        // Update reserves
        _updateReserves(pool, path[0], path[1], amountIn, outputAmount);
    }

    /**
     * @notice Returns the price of tokenA in terms of tokenB.
     * @dev The price is calculated based on the pool reserves. Returns 0 if the pool doesn't exist.
     * The price is returned with 18 decimals of precision.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return price The price of tokenA denominated in tokenB.
     */
    function getPrice(address tokenA, address tokenB) external view returns (uint256 price) {
        bytes32 poolId = _pairHash(tokenA, tokenB);
        LiquidityPool storage pool = pairPools[poolId];
        require(pool.reserveA > 0 && pool.reserveB > 0, "No liquidity available");

        (uint256 reserveA, uint256 reserveB) = _getReserves(pool, tokenA, tokenB);
        price = (reserveB * 1e18) / reserveA;
    }

    /**
     * @notice Estimates the output token amount for a given input
     */
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) 
        public pure returns (uint256 amountOut) {
        require(amountIn > 0 && reserveIn > 0 && reserveOut > 0, "Invalid input");
        amountOut = (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    /**
     * @dev Helper function to get reserves in the correct order
     */
    function _getReserves(LiquidityPool storage pool, address tokenA, address tokenB) 
        internal view returns (uint256 reserveA, uint256 reserveB) {
        bytes32 poolId = _pairHash(tokenA, tokenB);
        (address tMin, address tMax) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        if (tokenA == tMin) {
            return (pool.reserveA, pool.reserveB);
        } else {
            return (pool.reserveB, pool.reserveA);
        }
    }

    /**
     * @dev Helper function to update reserves in the correct order
     */
    function _updateReserves(LiquidityPool storage pool, address tokenIn, address tokenOut, 
        uint256 amountIn, uint256 amountOut) internal {
        bytes32 poolId = _pairHash(tokenIn, tokenOut);
        (address tMin, address tMax) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        
        if (tokenIn == tMin) {
            pool.reserveA += amountIn;
            pool.reserveB -= amountOut;
        } else {
            pool.reserveB += amountIn;
            pool.reserveA -= amountOut;
        }
    }

   /**
     * @notice Calculates the integer square root of a number.
     * @dev Uses the Babylonian method for integer square root.
     * @param y The number to calculate the square root of.
     * @return z The integer square root of y.
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    /**
     * @dev Simple minimum function
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}