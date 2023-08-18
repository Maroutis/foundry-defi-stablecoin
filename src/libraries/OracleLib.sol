// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OraleLib
 * @author Maroutis
 * @notice This library is used to check the chainlink Oracle for stale data
 * If a price is stale, the function will revert, and render the DCEngine unusable - this is by design
 * We want the DSCEngine to freeze if prices become stale.
 *
 * So if the chainlink network explodes and you have a lot of money locked in the protocol
 */

library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours; // 3* 60 * 60 = 10800 seconds

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        if (updatedAt == 0) {
            // roundId is the "round" the answer was created in. Every time a Chainlink network updates a price feed,
            // they add 1 to the round.
            // answeredInRound: Deprecated - Previously used when answers could take multiple rounds to be computed
            revert OracleLib__StalePrice();
        }
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function getTimeout() public pure returns (uint256) {
        return TIMEOUT;
    }
}
