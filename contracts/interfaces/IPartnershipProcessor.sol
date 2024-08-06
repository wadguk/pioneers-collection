// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPartnershipProcessor {
    struct ProjectSettings {
        uint256[] subIndexes;
        uint256[] levelFees;
        uint256 partnerFee;
        uint256 discount;
        bool constantDiscount;
    }

    struct PartnerPools {
        address gameDevPool;
        address partnerPool;
    }

    function processPartnershipOperation(address shareholder, uint256 initialFee, uint256 subIndex) external payable returns (uint256);
    
    function distributeFunds(address shareholder, uint256 subIndex) external payable;

    function storePartnerLinkWithTokenId(address shareholder, uint256 tokenId) external;

    function setProject(address dapp, uint256 subIndex, uint256 partnerFee, uint256[] memory levelFees, uint256 discount, bool constantDiscount) external;
        
    function calculateCommission(address dapp, uint256 amount, uint8 level, uint256 subIndex) external view returns (uint256);
    
    function calculateDiscount(address dapp, uint256 amount, uint256 subIndex) external view returns (uint256);
    
    function applyDiscount(address dapp, uint256 fee, uint256 subIndex) external view returns(uint256);
    
    function getProjectDiscountPercent(address dapp, uint256 subIndex) external view returns (uint256);    

    function getPartnerOfTokenId(uint256 tokenId) external view returns (address);
    
    function getPartnerTotalMinted(address partner) external view returns (uint256);
}
