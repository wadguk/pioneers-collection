// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IReferralRegistry.sol";
import "./interfaces/IPartnershipProcessor.sol";

/**
 * @title PartnershipProcessor
 * @dev A smart contract for handling partnership operations with access control.
 */
contract PartnershipProcessor is IPartnershipProcessor, AccessControl, ReentrancyGuard {
    IReferralRegistry public immutable REGISTRY;

    bytes32 public constant TRUSTED_SIGNER_ROLE = keccak256("TRUSTED_SIGNER_ROLE");
    bytes32 public constant TRUSTED_DAPP_ROLE = keccak256("TRUSTED_DAPP_ROLE");
    uint8 private constant MAX_REFERRAL_LEVEL = 30;

    // Mapping to track whether a discount has been used by a user for a specific DApp.
    mapping(address => mapping(address => bool)) public usedDiscounts;
    // Mapping to store project settings for DApps.
    mapping(address => mapping(uint256 => ProjectSettings)) public projects;
    // Mapping to store partner pools for community partners.
    mapping(address => PartnerPools) public partnerPools;
    // Mapping to store partner links with token ID.
    mapping(uint256 => address) private _partnerOf;
    // Mapping to store total minted tokens within the partner.
    mapping(address => uint256) private _partnerTotalMinted;

    event OperationProcessed(address dapp, address partner, address shareholder, uint256 msgValue);
    event ProjectSet(address dapp, uint256 subIndex, uint256 partnerFee, uint256[] levelFees, uint256 discount, bool constantDiscount);
    event PartnerLinkWithTokenIdStored(address partner, uint256 tokenId);

    error EthTransferFailed();
    error InvalidGameDevPool(uint256 index);
    error InvalidPartnerPool(uint256 index);
    error InvalidLevel(uint256 level, uint256 maxLevel);
    error NotCommunityOwner(address partner);
    error DappAddressZero();
    error PartnerFeeOutOfRange(uint256 fee);
    error DiscountOutOfRange(uint256 discount);
    error InvalidLevelFeesLength(uint256 length, uint256 maxLevel);

    /**
     * @dev Constructor to initialize the PartnershipProcessor contract.
     * @param referralRegistry The address of the ReferralRegistry contract.
     */
    constructor(address referralRegistry) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(TRUSTED_SIGNER_ROLE, _msgSender());
        REGISTRY = IReferralRegistry(referralRegistry);
    }

    /**
     * @dev Process a partnership operation and apply discounts if eligible.
     * @param shareholder The address of the referee (user making the referral).
     * @param initialFee The initial fee before applying discounts.
     * @param subIndex The sub-index of the referral project.
     * @return discountValue The discount applied to the operation.
     */
    function processPartnershipOperation(
        address shareholder,
        uint256 initialFee,
        uint256 subIndex
    )
        external
        payable
        nonReentrant
        onlyRole(TRUSTED_DAPP_ROLE) 
        returns (uint256 discountValue)
    {
        if (REGISTRY.isReferee(shareholder)) {
            uint256 initialMsgValue = msg.value;
            bool isDiscountEligible = shouldApplyDiscount(_msgSender(), shareholder, subIndex);
            if(!projects[_msgSender()][subIndex].constantDiscount){
                usedDiscounts[shareholder][_msgSender()] = true;
            }
            discountValue = isDiscountEligible ? calculateDiscount(_msgSender(), initialFee, subIndex) : 0;
            _distributeFunds(_msgSender(), shareholder, subIndex);
            emit OperationProcessed(_msgSender(), REGISTRY.getReferrer(shareholder), shareholder, initialMsgValue);
        } else {
            _transferEth(_msgSender(), msg.value);
        }
    }

    /**
     * @dev Distribute funds to various recipients for a specific shareholder.
     * @param shareholder The address of the shareholder (user making the referral).
     * @param subIndex The sub-index of the referral project.
     */
    function distributeFunds(
        address shareholder,
        uint256 subIndex
    ) external payable nonReentrant onlyRole(TRUSTED_DAPP_ROLE) {
        uint256 initialMsgValue = msg.value;
        _distributeFunds(_msgSender(), shareholder, subIndex);
        emit OperationProcessed(_msgSender(), REGISTRY.getReferrer(shareholder), shareholder, initialMsgValue);
    }

    /**
     * @dev Register partner pools for community partners.
     * @param partnerAddresses The addresses of community partners.
     * @param pools The corresponding partner pool settings.
     */
    function registerPartnerPools(
        address[] calldata partnerAddresses,
        PartnerPools[] calldata pools
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        for (uint256 i = 0; i < partnerAddresses.length; i++) {
            if (pools[i].gameDevPool == address(0)) revert InvalidGameDevPool(i);
            if (pools[i].partnerPool == address(0)) revert InvalidPartnerPool(i);
            if (!REGISTRY.isCommunityOwner(partnerAddresses[i])) revert NotCommunityOwner(partnerAddresses[i]);
            partnerPools[partnerAddresses[i]] = pools[i];
        }
    }

    /**
     * @dev Remove partner pools for community partners.
     * @param partnerAddresses The addresses of community partners.
     */
    function removePartnerPools(
        address[] calldata partnerAddresses
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        for (uint256 i = 0; i < partnerAddresses.length; i++) {
            delete partnerPools[partnerAddresses[i]];
        }
    }

    /**
     * @dev Set or update project settings for a specific DApp.
     * @param dapp The address of the DApp project.
     * @param subIndex The sub-index of the referral project.
     * @param partnerFee The partner fee percentage for the project.
     * @param levelFees The fees for each referral level in the project.
     * @param discount The discount percentage for the project.
     * @param constantDiscount A boolean indicating if the discount is constant.
     */
    function setProject(
        address dapp,
        uint256 subIndex,
        uint256 partnerFee,
        uint256[] calldata levelFees,
        uint256 discount,
        bool constantDiscount
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        if (dapp == address(0)) revert DappAddressZero();
        if (partnerFee > 10000) revert PartnerFeeOutOfRange(partnerFee);
        if (discount > 10000) revert DiscountOutOfRange(discount);
        if (levelFees.length > MAX_REFERRAL_LEVEL) revert InvalidLevelFeesLength(levelFees.length, MAX_REFERRAL_LEVEL);
        ProjectSettings storage project = projects[dapp][subIndex];
        project.partnerFee = partnerFee;
        project.levelFees = levelFees;
        project.discount = discount;
        project.constantDiscount = constantDiscount;
        _grantRole(TRUSTED_DAPP_ROLE, dapp);
        emit ProjectSet(dapp, subIndex, partnerFee, levelFees, discount, constantDiscount);
    }

    /**
     * @dev Associates a partner address with a given token ID.
     * @param shareholder The address of the shareholder.
     * @param tokenId The ID of the token to associate with the partner.
     */
    function storePartnerLinkWithTokenId(address shareholder, uint256 tokenId) external onlyRole(TRUSTED_DAPP_ROLE) {
        address partner = REGISTRY.getCommunityOwner(shareholder);
        if(partner != address(0)) {
            _partnerOf[tokenId] = partner;
            _partnerTotalMinted[partner] += 1;
            emit PartnerLinkWithTokenIdStored(partner, tokenId);
        }
    }

    /**
     * @dev Returns the partner address associated with the given token ID.
     * @param tokenId The ID of the token to retrieve the partner address for.
     * @return communityOwner The address of the partner associated with the token ID.
     */
    function getPartnerOfTokenId(uint256 tokenId) external view returns (address) {
        return _partnerOf[tokenId];
    }

    /**
     * @notice Returns the total number of tokens minted within a specific partner.
     * @param partner The address of the partner.
     * @return The total number of tokens minted within the partner.
     */
    function getPartnerTotalMinted(address partner) external view returns (uint256) {
        return _partnerTotalMinted[partner];
    }

    /**
     * @dev Get the discount percentage for a specific DApp project.
     * @param dapp The address of the DApp project.
     * @param subIndex The sub-index of the referral project.
     * @return discountPercent The discount percentage for the project.
     */
    function getProjectDiscountPercent(address dapp, uint256 subIndex) external view returns (uint256) {
        return projects[dapp][subIndex].discount;
    }

    /**
     * @dev Check if a discount should be applied to a referral operation.
     * @param dapp The address of the DApp project.
     * @param shareholder The address of the shareholder (user making the referral).
     * @param subIndex The sub-index of the referral project.
     * @return isDiscountEligible A boolean indicating if the discount is eligible for the operation.
     */
    function shouldApplyDiscount(
        address dapp,
        address shareholder,
        uint256 subIndex
    ) public view returns (bool) {
        bool hasValidReferrer = REGISTRY.isReferee(shareholder);
        if (projects[dapp][subIndex].constantDiscount) {
            return hasValidReferrer;
        } else {
            bool isDiscountedAlready = usedDiscounts[shareholder][dapp];
            return !isDiscountedAlready && hasValidReferrer;
        }
    }

     /**
     * @dev Calculate the commission for a specific referral level in a project.
     * @param dapp The address of the DApp project.
     * @param amount The amount for which to calculate the commission.
     * @param level The referral level for which to calculate the commission.
     * @param subIndex The sub-index of the referral project.
     * @return commission The calculated commission amount.
     */
    function calculateCommission(
        address dapp,
        uint256 amount,
        uint8 level,
        uint256 subIndex
    ) public view returns (uint256) {
        if (level >= projects[dapp][subIndex].levelFees.length) 
            revert InvalidLevel(level, projects[dapp][subIndex].levelFees.length);
        if (projects[dapp][subIndex].levelFees.length > 0) {
            uint256 commissionPercent = projects[dapp][subIndex].levelFees[level];
            return (amount * commissionPercent) / 10000;
        } else {
            return 0;
        }
    }

    /**
     * @dev Calculate the discount amount for a specific DApp project.
     * @param dapp The address of the DApp project.
     * @param fee The original fee before applying the discount.
     * @param subIndex The sub-index of the referral project.
     * @return discountAmount The calculated discount amount.
     */
    function calculateDiscount(address dapp, uint256 fee, uint256 subIndex) public view returns (uint256) {
       uint256 discountPercent = projects[dapp][subIndex].discount;
       return (fee * discountPercent) / 10000;
    }

    /**
     * @dev Apply the discount to a specific fee for a DApp project.
     * @param dapp The address of the DApp project.
     * @param fee The original fee before applying the discount.
     * @param subIndex The sub-index of the referral project.
     * @return discountedFee The final fee after applying the discount.
     */
    function applyDiscount(address dapp, uint256 fee, uint256 subIndex) public view returns (uint256) {
        return fee - calculateDiscount(dapp, fee, subIndex);
    }

    /**
     * @dev Internal function to transfer Ether to a recipient.
     * @param recipient The address of the recipient to transfer Ether to.
     * @param amount The amount of Ether to transfer.
     */
    function _transferEth(address recipient, uint256 amount) private {
        (bool callSuccess, ) = recipient.call{value: amount}("");
        if(!callSuccess) revert EthTransferFailed();
    }

    /**
     * @dev Private function to distribute funds to various recipients based on project settings.
     * @param dapp The address of the DApp project.
     * @param shareholder The address of the shareholder (user making the referral).
     * @param subIndex The sub-index of the referral project.
     */
    function _distributeFunds(address dapp, address shareholder, uint256 subIndex) private {
        if (REGISTRY.isReferee(shareholder)) {
            address currentReferrer = REGISTRY.getReferrer(shareholder);
            address currentPartner = REGISTRY.getCommunityOwner(shareholder);
            uint256 remainingAmount = msg.value;
            uint8 level = 0;

            if (projects[dapp][subIndex].partnerFee != 0) {
                uint256 partnerCommission = (remainingAmount * projects[dapp][subIndex].partnerFee) / 10000;
                uint256 gameDevCommission = (partnerCommission * 6000) / 10000;
                uint256 partnerPersonalCommission = (partnerCommission * 4000) / 10000;
                remainingAmount -= gameDevCommission + partnerPersonalCommission;
                _transferEth(partnerPools[currentPartner].gameDevPool, gameDevCommission);
                _transferEth(partnerPools[currentPartner].partnerPool, partnerPersonalCommission);
            }
            
            while (
                currentReferrer != address(0) &&
                level < projects[dapp][subIndex].levelFees.length
            ) {
                uint256 commission = calculateCommission(
                    dapp,
                    remainingAmount,
                    level,
                    subIndex
                );
                _transferEth(currentReferrer, commission);
                remainingAmount -= commission;

                currentReferrer = REGISTRY.getReferrer(currentReferrer);
                level++;
            }

            if (remainingAmount > 0) {
                _transferEth(dapp, remainingAmount);
            }
        }
    }
}