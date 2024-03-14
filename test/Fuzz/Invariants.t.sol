//SPDX-License-Identifier:MIT
 pragma solidity ^0.8.19;

import {Test , colsole} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";


contract InvariantsTest is Test,StdInvariant {
    DeployDSC deployer;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external{
        deployer = new DeployDSC();
        (dsc, dsce, config)  = deployer.run();
        (,,weth,btc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dsce,dsc);
        targetContract(address(dsce));

    }
    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view{
uint256 totalSupply = dsc.totalSupply();
uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

uint256 wethValue =  dsce.getUsdValue(weth,totalWethdeposited);
uint256 wbtcValue = dsce.getUsdValue(wbtc,totalBtcDeposited);
console.log("weth value:", wethValue);
console.log("weth value:", wbtcValue);
console.log("total supply:", totalSupply);
assert(wethValue + wbtcValue  >= totalSupply);
    }

} 