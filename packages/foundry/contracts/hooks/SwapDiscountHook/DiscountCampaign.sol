// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { IDiscountCampaign } from "./Interfaces/IDiscountCampaign.sol";
import { ISwapDiscountHook } from "./Interfaces/ISwapDiscountHook.sol";

contract DiscountCampaign is IDiscountCampaign, Ownable, ReentrancyGuard {
    // Public state variables
    CampaignDetails public campaignDetails;
    uint256 public tokenRewardDistributed;
    uint256 private _maxBuy;
    uint256 private _maxDiscount;

    // Private state variables
    ISwapDiscountHook private _swapHook;

    /**
     * @notice Initializes the discount campaign contract with the provided details.
     * @dev Sets the campaign details, owner, and swap hook address during contract deployment.
     * @param _campaignDetails A struct containing reward amount, expiration time, cooldown period, discount rate, and reward token.
     * @param _owner The owner address of the discount campaign contract.
     * @param _hook The address of the swap hook for tracking user discounts.
     */
    constructor(CampaignDetails memory _campaignDetails, address _owner, address _hook) Ownable(_owner) {
        campaignDetails = _campaignDetails;
        _swapHook = ISwapDiscountHook(_hook);
        _maxBuy = campaignDetails.rewardAmount;
        _maxDiscount = campaignDetails.discountRate;
    }

    /**
     * @notice Checks the validity of a token ID and ensures it meets the required conditions.
     * @dev Reverts if the token ID is invalid, expired, or if the reward has already been claimed.
     * @param tokenID The ID of the token to be validated.
     */
    modifier checkAndAuthorizeTokenId(uint256 tokenID) {
        (address user, address campaignAddress, , uint256 timeOfSwap, bool hasClaimed) = _swapHook.userDiscountMapping(
            tokenID
        );
        if (campaignAddress != address(this)) {
            revert InvalidTokenID();
        }
        if (timeOfSwap > campaignDetails.expirationTime) {
            revert DiscountExpired();
        }
        if (hasClaimed == true) {
            revert RewardAlreadyClaimed();
        }
        _;
    }

    /**
     * @notice Updates the campaign details.
     * @dev Only the contract owner can update the campaign details. This will replace the existing campaign parameters.
     * @param _newCampaignDetails A struct containing updated reward amount, expiration time, cooldown period, discount rate, and reward token.
     */
    function updateCampaignDetails(CampaignDetails calldata _newCampaignDetails) external {
        if (msg.sender != address(_swapHook)) revert NOT_AUTHORIZED();
        campaignDetails = _newCampaignDetails;
        emit CampaignDetailsUpdated(_newCampaignDetails);
    }

    /**
     * @notice Claims rewards for a specific token ID.
     * @dev Transfers the reward to the user associated with the token and marks the token as claimed.
     *      Reverts if the reward amount is zero or if the total rewards have been distributed.
     * @param tokenID The ID of the token for which the claim is made.
     */
    function claim(uint256 tokenID) public checkAndAuthorizeTokenId(tokenID) nonReentrant {
        (address user, , , , ) = _swapHook.userDiscountMapping(tokenID);
        uint256 reward = _getClaimableRewards(tokenID);

        if (reward == 0) {
            revert RewardAmountExpired();
        }

        IERC20(campaignDetails.rewardToken).transferFrom(address(this), user, reward);
        tokenRewardDistributed += reward;
        _maxBuy -= reward;
        _updateDiscount();
        _swapHook.setHasClaimed(tokenID);
    }

    /**
     * @notice Returns the claimable reward amount for a specific token ID.
     * @dev Fetches the claimable reward based on the token's associated swap data and discount rate.
     * @param tokenID The ID of the token to check.
     * @return The claimable reward amount.
     */
    function getClaimableReward(uint256 tokenID) external view returns (uint256) {
        return _getClaimableRewards(tokenID);
    }

    /**
     * @notice Internal function to calculate the claimable reward for a given token ID.
     * @dev The reward is calculated based on the swapped amount and discount rate.
     * @param tokenID The ID of the token for which to calculate the reward.
     * @return claimableReward The amount of reward that can be claimed.
     */
    function _getClaimableRewards(
        uint256 tokenID
    ) private view checkAndAuthorizeTokenId(tokenID) returns (uint256 claimableReward) {
        (, , uint256 swappedAmount, , ) = _swapHook.userDiscountMapping(tokenID);

        // Calculate claimable reward based on the swapped amount and discount rate
        if (swappedAmount <= _maxBuy) {
            claimableReward = (swappedAmount * campaignDetails.discountRate) / 100e18;
        } else {
            claimableReward = (_maxBuy * campaignDetails.discountRate) / 100e18;
        }
    }

    /**
     * @notice Updates the discount rate based on the distributed rewards.
     * @dev The discount rate decreases proportionally as more rewards are distributed.
     */
    function _updateDiscount() private {
        campaignDetails.discountRate = _maxDiscount * (1 - tokenRewardDistributed / campaignDetails.rewardAmount);
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        IERC20(tokenAddress).transferFrom(address(this), owner(), tokenAmount);
    }
}
