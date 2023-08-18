// SPDX-License-Identifier: MIT

// Have our invariant aka properties that should always hold

// Wht are our invariants ?

// 1. The total supply of DSC should be less than the total value of collateral
// 2. Getter view functions should never revert <-- evergreen invariant

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(engine));
        handler = new Handler(engine, dsc);
        targetContract(address(handler));
        // hey, don't call redeemCollateral, unless there is collateral to redeem
    }

    function invariant_protocolMustHaveMoreValueThatTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 wethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 wbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 wethValue = engine.getUsdValue(weth, wethDeposited);
        uint256 wbtcValue = engine.getUsdValue(wbtc, wbtcDeposited);

        console.log("wethValue: %s", wethValue);
        console.log("wbtcValue: %s", wbtcValue);
        console.log("total supply: %s", totalSupply);
        console.log("timesMintIsCalled: %s", handler.timesMintIsCalled());
        // console.log("maxDscToMint: %s", uint256(handler.maxDscToMint()));
        // console.log("totalDscMinted: %s", uint256(handler.totalDscMinted()));
        // console.log("collateralValueInUsd: %s", uint256(handler.collateralValueInUsd()));

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        engine.getAdditionalFeedPrecision();
        engine.getCollateralTokens();
        engine.getLiquidationBonus();
        engine.getLiquidationBonus();
        engine.getLiquidationThreshold();
        engine.getMinHealthFactor();
        engine.getPrecision();
        engine.getDsc();
    }

    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
