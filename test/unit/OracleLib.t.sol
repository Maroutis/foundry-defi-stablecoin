// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {OracleLib, AggregatorV3Interface} from "../../src/libraries/OracleLib.sol";

contract OracleLibTest is StdCheats, Test {
    MockV3Aggregator private ethUsdPriceFeed;

    uint8 private constant ETH_USD_DECIMALS = 8;
    int256 private constant ETH_USD_PRICE = 2000 ether;
    uint256 private constant TIMEOUT = 3 hours;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    function setUp() public {
        ethUsdPriceFeed = new MockV3Aggregator(ETH_USD_DECIMALS, ETH_USD_PRICE);
    }

    function testGetTimeout() public {
        uint256 timeout = OracleLib.getTimeout();
        assertEq(timeout, TIMEOUT);
    }

    function testRevertIfTimeout() public {
        vm.warp(block.timestamp + 3 hours + 1 seconds);
        vm.roll(block.number + 1); // n real network block and time progress hand in hand

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(ethUsdPriceFeed)));
    }

    function testStaleCheckLatestRoundData() public {
        vm.warp(block.timestamp + 3 hours - 1 seconds);
        vm.roll(block.number + 1); // n real network block and time progress hand in hand

        (, int256 answer,,,) = OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(ethUsdPriceFeed)));

        assertEq(answer, ETH_USD_PRICE);
    }

    function testPriceRevertsOnBadAnsweredInRound() public {
        uint80 _roundId = 0;
        int256 _answer = 0;
        uint256 _timestamp = 0;
        uint256 _startedAt = 0;
        ethUsdPriceFeed.updateRoundData(_roundId, _answer, _timestamp, _startedAt);

        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(ethUsdPriceFeed)));
    }
}
