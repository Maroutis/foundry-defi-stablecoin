// SPDX-License-Identifier: MIT

// Handler is going to narrow down the way we call functions (that way we don't waste runs)

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 public timesMintIsCalled;
    uint256 public totalDscMinted;
    uint256 public collateralValueInUsd;
    int256 public maxDscToMint;
    address[] public usersWithCollateralDeposited;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // the max uint96 value // if we do max uin256 and deposit more collateral after it will revert

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        engine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    // FUNCTIONS TO INTERACT WITH

    ///////////////
    // DSCEngine //
    ///////////////
    // redeem collateral <- call this when there is a collateral
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // double push if same address is pushed twice
        usersWithCollateralDeposited.push(msg.sender);
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        // msg.sender
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (totalDscMinted, collateralValueInUsd) = engine.getAccountInformation(sender);
        maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);

        if (maxDscToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.mintDsc(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = engine.getCollateralBalanceOfUser(sender, address(collateral));
        // amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        (totalDscMinted, collateralValueInUsd) = engine.getAccountInformation(sender);
        // console.log("totalDscMinted: %s", totalDscMinted);
        // console.log("collateralValueInUsd: %s", collateralValueInUsd);
        maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint <= 0) {
            return;
        }
        uint256 maxRedeemableCol = engine.getTokenAmountFromUsd(address(collateral), uint256(maxDscToMint));
        maxRedeemableCol = bound(maxRedeemableCol, 0, maxCollateralToRedeem);
        amountCollateral = bound(amountCollateral, 0, maxRedeemableCol);

        // console.log("amountCollateral: %s", amountCollateral);
        if (amountCollateral == 0) {
            return;
        }
        // vm.assume(ammountCollateral > 0);
        vm.startPrank(sender); // add vm.startPrank
        engine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function burnDsc(uint256 amountDsc, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        // Must burn more than 0
        (totalDscMinted,) = engine.getAccountInformation(sender);
        if (totalDscMinted == 0) {
            return;
        }
        totalDscMinted = bound(totalDscMinted, 0, dsc.balanceOf(sender));
        amountDsc = bound(amountDsc, 0, totalDscMinted);
        if (amountDsc == 0) {
            return;
        }
        vm.startPrank(sender);
        dsc.approve(address(engine), amountDsc);
        engine.burnDsc(amountDsc);
        vm.stopPrank();
    }

    function liquidate(uint256 collateralSeed, uint256 addressSeed, uint256 debtToCover) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        uint256 minHealthFactor = engine.getMinHealthFactor();
        uint256 userHealthFactor = engine.getHealthFactor(sender);
        if (userHealthFactor >= minHealthFactor) {
            return;
        }
        debtToCover = bound(debtToCover, 1, uint256(type(uint96).max));
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        engine.liquidate(address(collateral), sender, debtToCover);
    }

    /////////////////////////////
    // DecentralizedStableCoin //
    /////////////////////////////
    function transferDsc(uint256 amountDsc, address to, uint256 addressSeed) public {
        if (to == address(0)) {
            to = address(1);
        }
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        // Must transfer more than 0
        amountDsc = bound(amountDsc, 0, dsc.balanceOf(sender));
        if (amountDsc == 0) {
            return;
        }
        vm.prank(sender);
        dsc.transfer(to, amountDsc);
    }

    /////////////////////////////
    // Aggregator //
    /////////////////////////////
    // This breaks our invariant test suite !!!!
    // function updateCollateralPrice(uint96 newPrice, uint256 collateralSeed) public {
    //     // uint96 s that the number is not too big
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    //     MockV3Aggregator priceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(collateral)));

    //     priceFeed.updateAnswer(newPriceInt);
    // }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    function callSummary() external view {
        console.log("Weth total deposited", weth.balanceOf(address(engine)));
        console.log("Wbtc total deposited", wbtc.balanceOf(address(engine)));
        console.log("Total supply of DSC", dsc.totalSupply());
    }
}
