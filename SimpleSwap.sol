// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SimpleSwap
 * @author Lisandro Bigi
 * @dev This contract allows users to swap tokens, add/remove liquidity, and query prices.
 * It manages multiple liquidity pools within a single contract.
 */
contract SimpleSwap {

    struct Pool {
        uint112 reserve0;
        uint112 reserve1;
    }

    mapping(address => mapping(address => Pool)) public pools;
    mapping(address => mapping(address => mapping(address => uint256))) public userLiquidity;
    mapping(address => mapping(address => uint256)) public totalLiquidity;

    error SimpleSwap__Expired();
    error SimpleSwap__InsufficientAmount();
    error SimpleSwap__InsufficientLiquidity();
    error SimpleSwap__InvalidPath();
    error SimpleSwap__IdenticalAddresses();
    error SimpleSwap__TransferFailed();

    /**
     * @notice Sorts token addresses to ensure a unique pair representation.
     * @dev The pair (tokenA, tokenB) is the same as (tokenB, tokenA). To have a single representation,
     * we sort them by address.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return token0 The token with the lower address.
     * @return token1 The token with the higher address.
     */
    function _sortTokens(address tokenA, address tokenB) private pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert SimpleSwap__IdenticalAddresses();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /**
     * @notice Safely transfers ERC20 tokens from the sender to this contract.
     * @param token The address of the ERC20 token.
     * @param amount The amount of tokens to transfer.
     */
    function _safeTransferFrom(address token, uint256 amount) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount)
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SimpleSwap__TransferFailed();
        }
    }

    /**
     * @notice Safely transfers ERC20 tokens from this contract to a recipient.
     * @param token The address of the ERC20 token.
     * @param to The address of the recipient.
     * @param amount The amount of tokens to transfer.
     */
    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SimpleSwap__TransferFailed();
        }
    }
    
    /**
     * @notice Adds liquidity to an ERC-20 token pair pool.
     * @dev If the pool does not exist, it's created. The amount of liquidity tokens minted
     * is based on the ratio of the deposited assets.
     * @param tokenA The address of one of the tokens in the pair.
     * @param tokenB The address of the other token in the pair.
     * @param amountADesired The desired amount of tokenA to add.
     * @param amountBDesired The desired amount of tokenB to add.
     * @param amountAMin The minimum amount of tokenA to add, for slippage protection.
     * @param amountBMin The minimum amount of tokenB to add, for slippage protection.
     * @param to The address that will receive the liquidity tokens.
     * @param deadline The time after which the transaction will be reverted.
     * @return amountA The actual amount of tokenA added.
     * @return amountB The actual amount of tokenB added.
     * @return liquidity The amount of liquidity tokens minted.
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
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        if (block.timestamp > deadline) revert SimpleSwap__Expired();

        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        Pool storage pool = pools[token0][token1];

        if (pool.reserve0 == 0 && pool.reserve1 == 0) {
            amountA = amountADesired;
            amountB = amountBDesired;
        } else {
            uint256 amountBOptimal = (amountADesired * pool.reserve1) / pool.reserve0;
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) revert SimpleSwap__InsufficientAmount();
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = (amountBDesired * pool.reserve0) / pool.reserve1;
                if (amountAOptimal < amountAMin) revert SimpleSwap__InsufficientAmount();
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
        }
        
        if (amountA < amountAMin || amountB < amountBMin) revert SimpleSwap__InsufficientAmount();

        // Transfer tokens directly without intermediate variables
        if (tokenA == token0) {
            _safeTransferFrom(token0, amountA);
            _safeTransferFrom(token1, amountB);
        } else {
            _safeTransferFrom(token1, amountA);
            _safeTransferFrom(token0, amountB);
        }

        if (totalLiquidity[token0][token1] == 0) {
            liquidity = sqrt(amountA * amountB);
        } else {
            uint256 liquidity0 = (amountA * totalLiquidity[token0][token1]) / pool.reserve0;
            uint256 liquidity1 = (amountB * totalLiquidity[token0][token1]) / pool.reserve1;
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        }
        
        if (liquidity == 0) revert SimpleSwap__InsufficientLiquidity();

        totalLiquidity[token0][token1] += liquidity;
        userLiquidity[to][token0][token1] += liquidity;

        // Update reserves directly
        if (tokenA == token0) {
            pool.reserve0 += uint112(amountA);
            pool.reserve1 += uint112(amountB);
        } else {
            pool.reserve0 += uint112(amountB);
            pool.reserve1 += uint112(amountA);
        }

        return (amountA, amountB, liquidity);
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
    ) external returns (uint256 amountA, uint256 amountB) {
        if (block.timestamp > deadline) revert SimpleSwap__Expired();

        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        
        if (userLiquidity[msg.sender][token0][token1] < liquidity) revert SimpleSwap__InsufficientLiquidity();
        
        Pool storage pool = pools[token0][token1];

        uint256 amount0 = (liquidity * pool.reserve0) / totalLiquidity[token0][token1];
        uint256 amount1 = (liquidity * pool.reserve1) / totalLiquidity[token0][token1];
        
        if (tokenA == token0) {
            amountA = amount0;
            amountB = amount1;
        } else {
            amountA = amount1;
            amountB = amount0;
        }

        if (amountA < amountAMin || amountB < amountBMin) revert SimpleSwap__InsufficientAmount();

        userLiquidity[msg.sender][token0][token1] -= liquidity;
        totalLiquidity[token0][token1] -= liquidity;
        
        pool.reserve0 -= uint112(amount0);
        pool.reserve1 -= uint112(amount1);

        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);

        return (amountA, amountB);
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
    ) external returns (uint256[] memory amounts) {
        if (block.timestamp > deadline) revert SimpleSwap__Expired();
        if (path.length != 2) revert SimpleSwap__InvalidPath();

        address tokenIn = path[0];
        address tokenOut = path[1];
        (address token0, address token1) = _sortTokens(tokenIn, tokenOut);
        
        _safeTransferFrom(tokenIn, amountIn);

        Pool storage pool = pools[token0][token1];
        
        uint256 amountOut;
        if (tokenIn == token0) {
            amountOut = getAmountOut(amountIn, pool.reserve0, pool.reserve1);
            if (amountOut < amountOutMin) revert SimpleSwap__InsufficientAmount();
            pool.reserve0 += uint112(amountIn);
            pool.reserve1 -= uint112(amountOut);
        } else {
            amountOut = getAmountOut(amountIn, pool.reserve1, pool.reserve0);
            if (amountOut < amountOutMin) revert SimpleSwap__InsufficientAmount();
            pool.reserve1 += uint112(amountIn);
            pool.reserve0 -= uint112(amountOut);
        }

        _safeTransfer(tokenOut, to, amountOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
        
        return amounts;
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
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        Pool storage pool = pools[token0][token1];
        
        if (pool.reserve0 == 0 || pool.reserve1 == 0) return 0;
        
        if (tokenA == token0) {
            return (pool.reserve1 * 1e18) / pool.reserve0;
        } else {
            return (pool.reserve0 * 1e18) / pool.reserve1;
        }
    }

    /**
     * @notice Calculates the output amount for a given input amount and reserves.
     * @dev Implements the constant product formula with a 0.3% fee.
     * amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
     * @param amountIn The amount of input tokens.
     * @param reserveIn The reserve of the input token in the pool.
     * @param reserveOut The reserve of the output token in the pool.
     * @return amountOut The calculated amount of output tokens.
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) return 0;
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /**
     * @notice Calculates the integer square root of a number.
     * @dev Uses the Babylonian method for integer square root.
     * @param y The number to calculate the square root of.
     * @return z The integer square root of y.
     */
    function sqrt(uint256 y) private pure returns (uint256 z) {
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