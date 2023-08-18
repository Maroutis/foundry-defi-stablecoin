// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import "forge-std/console.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address btc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL_USER_FOR_LIQUIDATION = 30 ether;
    uint256 public constant AMOUNT_COLLATERAL_LIQUIDATOR = 40 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant MAXIMUM_MINT_AMOUNT = 5 ether;
    uint256 public constant MAXIMUM_MINT_AMOUNT_LIQUIDATOR = 20 ether;
    uint256 public constant SMALL_MINT_AMOUNT_LIQUIDATOR = 1 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, btc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL_LIQUIDATOR);
    }

    ///////////////////////////
    //// Costructor Tests ////
    /////////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMathPrceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////////
    //// Price Tests ////
    /////////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testgetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualweth = engine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualweth);
    }

    /////////////////////////////////
    //// DepositCollateral Tests ////
    ////////////////////////////////

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);

        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    function testRevertsIfTransferFromFails() public {
        // Arrange - Setup
        MockFailedTransferFrom mockWeth = new MockFailedTransferFrom();
        tokenAddresses = [address(mockWeth)];
        priceFeedAddresses = [ethUsdPriceFeed];

        DSCEngine mockEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );
        mockWeth.mint(USER, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        ERC20Mock(address(mockWeth)).approve(address(mockEngine), AMOUNT_COLLATERAL);
        // Act / Assert
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockEngine.depositCollateral(address(mockWeth), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);

        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    /////////////////////////////////
    //// Redeem Collateral Tests ////
    ////////////////////////////////

    function testRevertsIfRedeemAmountZero() public depositedCollateral {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);

        vm.stopPrank();
    }

    function testRevertsIfTransferFails() public {
        // Arrange - Setup
        MockFailedTransfer mockWETH = new MockFailedTransfer();
        tokenAddresses = [address(mockWETH)];
        priceFeedAddresses = [ethUsdPriceFeed];
        DSCEngine mockEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );
        mockWETH.mint(USER, AMOUNT_COLLATERAL);

        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(address(mockWETH)).approve(address(mockEngine), AMOUNT_COLLATERAL);
        // Act / Assert
        mockEngine.depositCollateral(address(mockWETH), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockEngine.redeemCollateral(address(mockWETH), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier redeemedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);

        vm.stopPrank();
        _;
    }

    function testCanRedeemCollateralAndGetAccountInfo() public depositedCollateral redeemedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(expectedTotalDscMinted, totalDscMinted);
        assertEq(0, expectedDepositAmount);
    }

    ////////////////////////////
    //// Mint Tokens Tests ////
    ///////////////////////////

    function testRevertsIfMintAmountZero() public depositedCollateral {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);

        vm.stopPrank();
    }

    function testRevertsIfHealthFactorIsBrokenWhenMinting() public {
        vm.startPrank(USER);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        engine.mintDsc(AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    modifier mintedDsc() {
        vm.startPrank(USER);

        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT);
        engine.mintDsc(maximumDscAmount);

        vm.stopPrank();
        _;
    }

    function testCanMintDsc() public depositedCollateral mintedDsc {
        vm.startPrank(USER);

        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT);
        uint256 balanceAfter = dsc.balanceOf(USER);
        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);
        assertEq(balanceAfter, totalDscMinted);
        assertEq(balanceAfter, maximumDscAmount);

        vm.stopPrank();
    }

    ////////////////////////////
    //// Burn Tokens Tests ////
    ///////////////////////////

    function testRevertsIfBurnAmountZero() public depositedCollateral {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.burnDsc(0);

        vm.stopPrank();
    }

    function testRevertsIfBurnTransferFromFails() public {
        // Arrange - Setup
        MockFailedTransferFrom mockDsc = new MockFailedTransferFrom();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        DSCEngine mockEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );

        mockDsc.transferOwnership(address(mockEngine));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockEngine), AMOUNT_COLLATERAL);
        mockEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT);
        mockEngine.mintDsc(maximumDscAmount);
        // Act / Assert
        ERC20Mock(address(mockDsc)).approve(address(mockEngine), maximumDscAmount);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockEngine.burnDsc(maximumDscAmount);
        vm.stopPrank();
    }

    modifier burnedDsc() {
        vm.startPrank(USER);

        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT);
        dsc.approve(address(engine), maximumDscAmount);
        engine.burnDsc(maximumDscAmount);

        vm.stopPrank();
        _;
    }

    function testCanBurn() public depositedCollateral mintedDsc burnedDsc {
        vm.startPrank(USER);

        uint256 balanceAfter = dsc.balanceOf(USER);
        uint256 balanceEngine = dsc.balanceOf(address(engine));
        (uint256 totalDscMinted,) = engine.getAccountInformation(USER);

        assertEq(balanceAfter, 0);
        assertEq(balanceAfter, totalDscMinted);
        assertEq(balanceEngine, 0);

        vm.stopPrank();
    }

    ////////////////////////////////////////////
    //// depositCollateralAndMintDsc Tests ////
    //////////////////////////////////////////

    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 amountToMint =
            (AMOUNT_COLLATERAL * (uint256(price) * engine.getAdditionalFeedPrecision())) / engine.getPrecision();

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        uint256 expectedHealthFactor =
            engine.calculateHealthFactor(amountToMint, engine.getUsdValue(weth, AMOUNT_COLLATERAL));
        console.log("expectedHealthFactor", expectedHealthFactor);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    function testRevertsIfMintFails() public {
        // Arrange - Setup
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        priceFeedAddresses = [ethUsdPriceFeed];
        DSCEngine mockEngine = new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockEngine));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(mockEngine), AMOUNT_COLLATERAL);

        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockEngine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, maximumDscAmount);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, maximumDscAmount);
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintedDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT);
        assertEq(userBalance, maximumDscAmount);
    }

    //////////////////////////////////////
    //// redeemCollateralForDsc Tests ////
    /////////////////////////////////////

    function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), MAXIMUM_MINT_AMOUNT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateralForDsc(weth, 0, MAXIMUM_MINT_AMOUNT);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, maximumDscAmount);
        dsc.approve(address(engine), maximumDscAmount);
        engine.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, maximumDscAmount);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    ////////////////////////
    // healthFactor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 expectedHealthFactor = 1 ether;
        uint256 healthFactor = engine.getHealthFactor(USER);

        assertEq(healthFactor, expectedHealthFactor);
    }

    function testHealthFactorCanGoBelowOne() public depositedCollateralAndMintedDsc {
        int256 ethUsdUpdatedPrice = 500e8; // 1 ETH = $18
        // Rememeber, we need $150 at all times if we have $100 of debt

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);

        uint256 userHealthFactor = engine.getHealthFactor(USER);
        // $180 collateral / 200 debt = 0.9
        assertEq(userHealthFactor, 0.25 ether);
    }

    //////////////////////////
    //// Liquidate Tests ////
    /////////////////////////

    function testRevertsIfLiquidationAmountZero() public depositedCollateral {
        vm.startPrank(USER);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.liquidate(weth, LIQUIDATOR, 0);

        vm.stopPrank();
    }

    function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
        ERC20Mock(weth).mint(LIQUIDATOR, AMOUNT_COLLATERAL_LIQUIDATOR);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL_LIQUIDATOR);
        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL_LIQUIDATOR, maximumDscAmount);
        dsc.approve(address(engine), maximumDscAmount);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, USER, maximumDscAmount);
        vm.stopPrank();
    }

    function testMustImproveHealthFactorOnLiquidation() public {
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL_USER_FOR_LIQUIDATION);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL_USER_FOR_LIQUIDATION);
        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL_USER_FOR_LIQUIDATION, maximumDscAmount);

        vm.stopPrank();

        MockV3Aggregator ethUsdPriceFeedContract = MockV3Aggregator(ethUsdPriceFeed);
        ethUsdPriceFeedContract.updateAnswer(100e8);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL_LIQUIDATOR);
        uint256 dscAmount = engine.getUsdValue(weth, SMALL_MINT_AMOUNT_LIQUIDATOR);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL_LIQUIDATOR, dscAmount);
        dsc.approve(address(engine), dscAmount);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
        engine.liquidate(weth, USER, dscAmount);

        vm.stopPrank();
    }

    modifier liquidated() {
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL_USER_FOR_LIQUIDATION);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL_USER_FOR_LIQUIDATION);
        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL_USER_FOR_LIQUIDATION, maximumDscAmount);

        vm.stopPrank();

        MockV3Aggregator ethUsdPriceFeedContract = MockV3Aggregator(ethUsdPriceFeed);
        ethUsdPriceFeedContract.updateAnswer(500e8);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL_LIQUIDATOR);
        maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT_LIQUIDATOR);
        engine.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL_LIQUIDATOR, maximumDscAmount);
        dsc.approve(address(engine), maximumDscAmount);
        engine.liquidate(weth, USER, maximumDscAmount);

        vm.stopPrank();
        _;
    }

    function testLiquidationPayoutIsCorrect() public liquidated {
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT_LIQUIDATOR);
        uint256 expectedWeth = engine.getTokenAmountFromUsd(weth, maximumDscAmount)
            + (engine.getTokenAmountFromUsd(weth, maximumDscAmount) / engine.getLiquidationBonus());
        uint256 hardCodedExpected = 22000000000000000000;
        assertEq(liquidatorWethBalance, hardCodedExpected);
        assertEq(liquidatorWethBalance, expectedWeth);
    }

    function testUserStillHasSomeEthAfterLiquidation() public liquidated {
        // Get how much WETH the user lost
        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT_LIQUIDATOR);
        uint256 amountLiquidated = engine.getTokenAmountFromUsd(weth, maximumDscAmount)
            + (engine.getTokenAmountFromUsd(weth, maximumDscAmount) / engine.getLiquidationBonus());

        uint256 usdAmountLiquidated = engine.getUsdValue(weth, amountLiquidated);
        uint256 expectedUserCollateralValueInUsd =
            engine.getUsdValue(weth, AMOUNT_COLLATERAL_USER_FOR_LIQUIDATION) - (usdAmountLiquidated);

        (, uint256 userCollateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 hardCodedExpectedValue = 4000000000000000000000;
        assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
        assertEq(userCollateralValueInUsd, hardCodedExpectedValue);
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = engine.getAccountInformation(LIQUIDATOR);
        uint256 maximumDscAmount = engine.getUsdValue(weth, MAXIMUM_MINT_AMOUNT_LIQUIDATOR);
        assertEq(liquidatorDscMinted, maximumDscAmount);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = engine.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }

    ///////////////////////////////////
    // View & Pure Function Tests ////
    //////////////////////////////////

    function testGetCollateralTokenPriceFeed() public {
        address priceFeed = engine.getCollateralTokenPriceFeed(weth);
        assertEq(priceFeed, ethUsdPriceFeed);
    }

    function testGetCollateralTokens() public {
        address[] memory collateralTokens = engine.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinHealthFactor() public {
        uint256 minHealthFactor = engine.getMinHealthFactor();
        assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public {
        uint256 liquidationThreshold = engine.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        (, uint256 collateralValue) = engine.getAccountInformation(USER);
        uint256 expectedCollateralValue = engine.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(btc).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        ERC20Mock(btc).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(btc, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 collateralValue = engine.getAccountCollateralValue(USER);
        uint256 expectedCollateralValue =
            engine.getUsdValue(weth, AMOUNT_COLLATERAL) + engine.getUsdValue(btc, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(btc).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
        ERC20Mock(btc).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(weth, AMOUNT_COLLATERAL);
        engine.depositCollateral(btc, AMOUNT_COLLATERAL);
        vm.stopPrank();
        uint256 wethCollateralValue = engine.getCollateralBalanceOfUser(USER, weth);
        uint256 btcCollateralValue = engine.getCollateralBalanceOfUser(USER, btc);
        uint256 wethCollateralValueInUsd = engine.getUsdValue(weth, wethCollateralValue);
        uint256 btcCollateralValueInUsd = engine.getUsdValue(btc, btcCollateralValue);
        uint256 hardCodedExpectedValue = 40000000000000000000000;
        assertEq(wethCollateralValueInUsd + btcCollateralValueInUsd, hardCodedExpectedValue);
    }

    function testGetDsc() public {
        address dscAddress = engine.getDsc();
        assertEq(dscAddress, address(dsc));
    }
}
