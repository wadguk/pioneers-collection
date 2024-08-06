// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPioneersCollection  {
    struct SubcollectionParams {
        string name;
        string baseCID;
        bytes32 merkleRoot;
        uint256 mintFee;
        uint256 mainSupply;
        uint256 goldSupply;
        uint256 availableMainSupply;
        uint256 maxMintPerAddress;
    }

    struct Subcollection {
        SubcollectionParams params;
        uint256 totalMinted;
        uint256 startIndex;
        uint256 endIndex;
        bool whitelistMintEnabled;
        bool openMintEnabled;
        bool burnEnabled;
        bool locked;
    }

    function addSubcollection(SubcollectionParams calldata params) external;

    function mint(string calldata subcollectionName, address to, bytes32[] memory proof, uint256 mintAmount, uint256 initialFee) external payable;
    
    function setTokenCID(uint256 tokenId, string calldata cid) external;
    
    function setMerkleRoot(string calldata subcollectionName, bytes32 root) external;

    function setMintFee(string calldata subcollectionName, uint256 newMintFee) external;

    function setMaxMintPerAddress(string calldata subcollectionName, uint256 maxMintPerAddress) external;

    function setTrustedForwarder(address forwarder) external;

    function setWhitelistMintEnabled(string calldata subcollectionName, bool whitelistMintEnabled) external;

    function setBlacklist(address adrs, bool ban) external;

    function setBurnEnabled(string calldata subcollectionName, bool burnEnabled) external;

    function setRoyaltyInfo(address receiver, uint96 royaltyFeesInBips) external;

    function setIncomeVault(address payable newIncomeVault) external;

    function totalSupply() external view returns (uint256);

    function contractURI() external view returns (string memory);

    function getSubcollection(uint256 subcollectionId) external view returns (Subcollection memory);

    function getSubcollectionIdxByTokenId(uint256 tokenId) external view returns (uint256);

    function getSubcollectionIdxByName(string memory subcollectionName) external view returns (uint256);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function tokenURI(uint256 tokenId) external view returns (string memory);

    function CLAIMER_ROLE() external view returns (bytes32);

    function mintGoldenToken(string calldata subcollectionName, uint256[] calldata goldenTicketNumbers, address to) external;

    function subcollectionsCount() external view returns (uint256);
    
    function mintedBy(address user, uint256 subcollectionIdx) external view returns (uint256);
}