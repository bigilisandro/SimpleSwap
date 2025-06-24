# SimpleSwap - Mejorado

## Descripción

SimpleSwap es un contrato de Automated Market Maker (AMM) que permite intercambiar tokens ERC-20, agregar/remover liquidez y consultar precios. Esta versión ha sido mejorada basándose en las mejores prácticas de SimpleSwapV2.

## Mejoras Implementadas

### 1. **Sistema de LP Tokens ERC20**
- **Antes**: Sistema manual de tracking de liquidez por usuario
- **Ahora**: Tokens ERC20 estándar ("Pool Share Token" - PST) que representan la participación en los pools
- **Beneficio**: Mayor compatibilidad, transferibilidad y estándar de la industria

### 2. **Estructura de Datos Simplificada**
- **Antes**: Múltiples mappings complejos (`pools`, `userLiquidity`, `totalLiquidity`)
- **Ahora**: Un solo mapping `pairPools` con struct `LiquidityPool`
- **Beneficio**: Código más limpio, menor complejidad y mejor gas efficiency

### 3. **Manejo de Errores Mejorado**
- **Antes**: Custom errors con nombres específicos
- **Ahora**: Mensajes de error descriptivos con `require()`
- **Beneficio**: Mejor experiencia de usuario y debugging

### 4. **Funciones de Transferencia Simplificadas**
- **Antes**: Funciones `_safeTransfer` y `_safeTransferFrom` con low-level calls
- **Ahora**: Llamadas directas a `IERC20.transfer()` y `IERC20.transferFrom()`
- **Beneficio**: Código más simple y menos propenso a errores

### 5. **Cálculo de Liquidez Mejorado**
- **Antes**: Lógica compleja con múltiples condiciones
- **Ahora**: Algoritmo más directo usando `Math.min()` y `Math.sqrt()`
- **Beneficio**: Mayor precisión y simplicidad

### 6. **Identificación de Pools**
- **Antes**: Ordenamiento de tokens con `_sortTokens()`
- **Ahora**: Hash único con `_pairHash()` usando `keccak256`
- **Beneficio**: Mayor eficiencia y unicidad garantizada

## Funciones Principales

### 1. `addLiquidity()`
Agrega liquidez a un pool y acuña tokens LP.

### 2. `removeLiquidity()`
Remueve liquidez del pool y quema tokens LP.

### 3. `swapExactTokensForTokens()`
Intercambia una cantidad exacta de tokens de entrada por tokens de salida.

### 4. `getPrice()`
Obtiene el precio actual de un token en términos de otro.

### 5. `getAmountOut()`
Calcula la cantidad de salida para una cantidad de entrada dada.

## Diferencias Clave con SimpleSwapV2

| Aspecto | SimpleSwap Original | SimpleSwap Mejorado | SimpleSwapV2 |
|---------|-------------------|-------------------|--------------|
| LP Tokens | Manual tracking | ERC20 tokens | ERC20 tokens |
| Estructura | Múltiples mappings | Struct único | Struct único |
| Errores | Custom errors | Require messages | Require messages |
| Transferencias | Low-level calls | Direct calls | Direct calls |
| Identificación | Token sorting | Hash-based | Hash-based |

## Ventajas de la Versión Mejorada

1. **Compatibilidad**: Tokens LP estándar ERC20
2. **Simplicidad**: Código más limpio y mantenible
3. **Eficiencia**: Menor uso de gas
4. **Robustez**: Mejor manejo de errores
5. **Escalabilidad**: Estructura más flexible para futuras mejoras

## Uso

```solidity
// Agregar liquidez
addLiquidity(
    tokenA,
    tokenB,
    amountADesired,
    amountBDesired,
    amountAMin,
    amountBMin,
    to,
    deadline
);

// Intercambiar tokens
swapExactTokensForTokens(
    amountIn,
    amountOutMin,
    [tokenIn, tokenOut],
    to,
    deadline
);

// Consultar precio
uint256 price = getPrice(tokenA, tokenB);
```

## Verificación

El contrato está diseñado para ser compatible con verificadores de Etherscan y otros exploradores de bloques, siguiendo las mejores prácticas de OpenZeppelin y estándares ERC20. 