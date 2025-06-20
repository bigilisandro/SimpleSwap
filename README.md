# SimpleSwap

## 🎯 Objective

This project implements a smart contract called `SimpleSwap` that replicates the core functionality of an Automated Market Maker (AMM) like Uniswap V2. It allows users to add and remove liquidity, swap tokens, and query prices without relying on external protocols.

## ✨ Features

*   **Add Liquidity**: Provide liquidity to a token pair pool and receive liquidity tokens in return.
*   **Remove Liquidity**: Burn liquidity tokens to withdraw your share of the underlying assets.
*   **Swap Tokens**: Exchange one ERC-20 token for another.
*   **Get Price**: Fetch the current exchange rate between two tokens based on pool reserves.
*   **Calculate Swap Output**: Determine the expected output amount for a given input amount before executing a swap.

## 📜 Smart Contract Functions

The `SimpleSwap.sol` contract exposes the following functions:

### `addLiquidity`

Adds liquidity to a specific token pair pool.

```solidity
function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
```

### `removeLiquidity`

Removes liquidity from a token pair pool.

```solidity
function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
) external returns (uint256 amountA, uint256 amountB);
```

### `swapExactTokensForTokens`

Swaps an exact amount of an input token for another token.

```solidity
function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
) external returns (uint256[] memory amounts);
```

### `getPrice`

Returns the price of one token in terms of another, with 18 decimals of precision.

```solidity
function getPrice(address tokenA, address tokenB) external view returns (uint256 price);
```

### `getAmountOut`

Calculates the amount of output tokens you will receive for a given amount of input tokens.

```solidity
function getAmountOut(
    uint256 amountIn,
    uint256 reserveIn,
    uint256 reserveOut
) external pure returns (uint256 amountOut);
```

## 🚀 How to Use

1.  **Deploy**: Deploy the `SimpleSwap.sol` contract to an Ethereum network.
2.  **Approve Tokens**: Before adding liquidity or swapping, you must approve the `SimpleSwap` contract to spend your ERC-20 tokens by calling the `approve` function on the respective token contracts.
3.  **Interact**: Call the contract's functions to add/remove liquidity or perform swaps. 