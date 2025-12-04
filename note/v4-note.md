## v4 note

scrapy vs uni v4

solmate v4core的依赖库

### 权限开启，官方推荐这种，明确写出的方式
```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
    return Hooks.Permissions({
        beforeInitialize: false,
        afterInitialize: false,
        beforeAddLiquidity: true,
        afterAddLiquidity: false,
        beforeRemoveLiquidity: true,
        afterRemoveLiquidity: false,
        beforeSwap: true,
        afterSwap: true,
        beforeDonate: false,
        afterDonate: false,
        beforeSwapReturnDelta: false,
        afterSwapReturnDelta: false,
        afterAddLiquidityReturnDelta: false,
        afterRemoveLiquidityReturnDelta: false
    });
}
```

### solidity中未使用到的参数
```solidity
    function _beforeSwap(address, PoolKey calldata params, SwapParams calldata, bytes calldata)
```
如果params参数在函数体中从未被应用到。那么
```solidity
// 直接不写
    function _beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
    // 写出下划线，表示未使用
    function _beforeSwap(address, PoolKey calldata _params, SwapParams calldata, bytes calldata)
```



### 常用命令
输出级别：
-v: 只显示测试结果
-vv: 显示 console.log 输出 ⭐
-vvv: 显示调用栈
-vvvv: 显示更详细的 trace
```shell
# 运行所有 Fee 测试
forge test --match-contract FeeTest -vvv
# 运行特定测试
forge test --match-test testSwapZeroForOne -vvv
# 运行测试并查看 gas 使用情况
forge test --match-contract FeeTest --gas-report
```

### beforeSwapDelta
返回三个参数，本身的函数选择器，，包含两个代币价格的delta数据，，还有费率


### console.log
```solidity

import {console} from "forge-std/console.sol";

// 使用示例
console.log("Value:", value);
console.log("amountOut", amountOut);
console.log("Address:", address(this));
console.logInt(int256Value);
// 基本类型
console.log("string", uint256);
console.log("string", int256);
console.log("string", address);
console.log("string", bool);

// 多个参数（最多 4 个）
console.log("a", a, "b", b);

// 不同类型的特定方法
console.logInt(int256);
console.logUint(uint256);
console.logString(string);
console.logBytes(bytes);
console.logBytes32(bytes32);
console.logAddress(address);
console.logBool(bool);
```

### console2.log

```solidity
import {console2} from "forge-std/console2.sol";
import {console2} from "forge-std/console2.sol";

// 支持更多类型
console2.log("Hex:", bytes32(value));
console2.log("Bool:", true);
// 支持更多类型
console2.log("Hex:", bytes32(value));
console2.log("Bool:", true);
```