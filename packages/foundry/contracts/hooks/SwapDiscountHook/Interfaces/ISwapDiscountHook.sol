// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

/**
 * @title ISwapDiscountHook
 * @notice Interface for the Swap Discount Hook, which manages the granting of discounts during swaps.
 */
interface ISwapDiscountHook {
    /// @notice Reverts if the provided campaign address is invalid.
    error InvalidCampaignAddress();
}
