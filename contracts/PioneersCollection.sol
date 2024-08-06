// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@opengsn/contracts/src/ERC2771Recipient.sol";
import "./interfaces/IPioneersCollection.sol";
import "./interfaces/IPartnershipProcessor.sol";

/**
 * @title PioneersCollection
 * @dev The Pioneers Collection contract for minting and managing NFTs from different subcollections.
 */
contract PioneersCollection is
    IPioneersCollection,
    IERC721Metadata,
    ERC721,
    ERC2981,
    AccessControl,
    ERC2771Recipient
{
    using Strings for uint256;

    IPartnershipProcessor public immutable PROCESSOR;

    //The bytes32 constants representing different roles in the contract.
    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER_ROLE");
    bytes32 public constant TRUSTED_SIGNER_ROLE = keccak256("TRUSTED_SIGNER_ROLE");

    // Contract metadata CID.
    string private _contractMetadataCID;
    // Maximum supply for this collection.
    uint256 public totalSupply;
    // Base URL link.
    string private _baseURL;
    // Income vault address.
    address payable public incomeVault;

    // Mapping for token CIDs.
    mapping(uint256 => string) private _tokenCIDs;
    // Whitelist for trusted marketplaces.
    mapping(address => bool) private _blacklist;
    // Used for random index assignment.
    mapping(uint256 => mapping(uint256 => uint256)) private _tokenMatrix;
    // Mapping for mint limit per address.
    mapping(address => mapping(uint256 => uint256)) private _totalMinted;
    // Look up mapping for subcollection IDs.
    mapping(bytes32 => uint256) private _subIdByNameHash;
    // Look up mapping for subcollection IDs.
    mapping(uint256 => uint256) private _subIdByTokenId;

    Subcollection[] public subcollections;

    event AvailableMainSupplyUpdated(string subcollectionName, uint256 availableMainSupply);
    event BaseURLUpdated(string baseURL);
    event BlacklistStatusChanged(address indexed account, bool indexed banned);
    event BurnEnabled(string subcollectionName, bool indexed enabled);
    event ContractMetadataUpdated(string uri);
    event MaxMintPerAddressChanged(string subcollectionName, uint256 indexed count);
    event MerkleRootChanged(string subcollectionName, bytes32 root);
    event MetadataUpdate(uint256 indexed _tokenId);
    event MintFeeChanged(string subcollectionName, uint256 indexed mintFee);
    event SubcollectionAdded(Subcollection subcollection);
    event SubcollectionSold(string subcollectionName);
    event SubcollectionSetLocked(string subcollectionName);
    event RoyaltyInfoUpdated(address receiver, uint96 royaltyFeesInBips);
    event IncomeVaultUpdated(address newIncomeVault);
    event OpenMintEnabled(string subcollectionName, bool indexed enabled);
    event TrustedForwarderChanged(address indexed forwarder);
    event WhitelistMintEnabled(string subcollectionName, bool indexed enabled);

    error AvailableMainSupplyExceeded();
    error DuplicateName();
    error EthTransferFailed();
    error InvalidCollection();
    error InvalidCollectionName();
    error InvalidMainSupply();
    error InvalidMaxMintPerAddress();
    error InvalidMintFee();
    error InvalidMintAmount();
    error InvalidMsgValue();
    error InvalidInitialFee();
    error InvalidVrfRequest();
    error InvalidTokenID();
    error MainSupplyExceeded();
    error MaxSupplyPerAddressExceeded();
    error MintNotAllowed();
    error MissingBaseCID();
    error MissingName();
    error NoNestedCollections();
    error NotOnWhitelist();
    error NotTokenOwnerNorApproved();
    error SubcollectionLocked();
    error SubcollectionSoldOut();
    error SubscriptionLowBalance();
    error TokenDoesNotExist();
    error ZeroAddress();

    receive() external payable{} 

    /**
     * @dev Contract constructor used to initialize the ERC721 token.
     * @param name The name of the ERC721 token.
     * @param symbol The symbol of the ERC721 token.
     * @param baseURL The base URL for token metadata.
     * @param contractMetadataCID The CID of the contract metadata.
     * @param partnershipProcessor The address of the PartnershipProcessor contract.
     */
    constructor(
        string memory name,
        string memory symbol,
        string memory baseURL,
        string memory contractMetadataCID,
        address partnershipProcessor
    ) ERC721(name, symbol){
        PROCESSOR = IPartnershipProcessor(partnershipProcessor);
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(TRUSTED_SIGNER_ROLE, _msgSender());
        _contractMetadataCID = contractMetadataCID;
        _baseURL = baseURL;
    }

    /**
     * @dev Allows the trusted signer to add a new sub collection.
     * @param params The params of the sub collection that will be added.
     */
    function addSubcollection(
        SubcollectionParams calldata params
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        if (bytes(params.name).length == 0) revert MissingName();
        if (bytes(params.baseCID).length == 0) revert MissingBaseCID();
        if (params.mainSupply == 0) revert InvalidMainSupply();
        if (params.mintFee == 0) revert InvalidMintFee();
        if (params.maxMintPerAddress == 0) revert InvalidMaxMintPerAddress();
        
        bytes32 subcollectionNameHash = keccak256(abi.encodePacked(params.name));
        if (subcollections.length != 0) {
            if (keccak256(abi.encodePacked(
                subcollections[_subIdByNameHash[subcollectionNameHash]].params.name)) == subcollectionNameHash)
            revert DuplicateName();
        }

        _subIdByNameHash[subcollectionNameHash] = subcollections.length;
        uint256 startIndex = subcollections.length > 0
            ? subcollections[subcollections.length - 1].endIndex +
                subcollections[subcollections.length - 1].params.goldSupply + 1
            : 0;
        uint256 endIndex = startIndex + params.mainSupply - 1;

        subcollections.push(
            Subcollection({
                params: params,
                totalMinted: 0,
                startIndex: startIndex,
                endIndex: endIndex,
                whitelistMintEnabled: true,
                openMintEnabled: false,
                burnEnabled: false,
                locked: false
            })
        );

        totalSupply += (params.mainSupply + params.goldSupply);
        emit SubcollectionAdded(subcollections[subcollections.length - 1]);
    }

    /**
     * @dev Removes a subcollection from the contract.
     * @param subcollectionName The name of the subcollection to be removed.
     */
    function removeSubcollection(string calldata subcollectionName) external onlyRole(TRUSTED_SIGNER_ROLE) {
        uint256 subcollectionIdx = getSubcollectionIdxByName(subcollectionName);
        if (bytes(subcollections[subcollectionIdx].params.name).length == 0) revert InvalidCollectionName();
        if (subcollections[subcollectionIdx].locked) revert SubcollectionLocked();

        totalSupply -= (subcollections[subcollectionIdx].params.mainSupply + subcollections[subcollectionIdx].params.goldSupply);
        subcollections[subcollectionIdx] = subcollections[subcollections.length - 1];
        delete subcollections[subcollections.length - 1];
        subcollections.pop();
        bytes32 subcollectionNameHash = keccak256(abi.encodePacked(subcollectionName));
        delete _subIdByNameHash[subcollectionNameHash];
    }

    /**
     * @dev Function to mint a new token.
     * @param subcollectionName subcollection name.
     * @param to Address of the recipient who will receive the token.
     * @param proof Proof containing elements hashed with the recipient's address, to check if it is on the whitelist.
     * @param initialFee The initial fee before discount.
     */
    function mint(
        string calldata subcollectionName,
        address to,
        bytes32[] memory proof,
        uint256 mintAmount,
        uint256 initialFee
    ) external payable {
        if(mintAmount == 0) revert InvalidMintAmount();
        if(initialFee == 0) revert InvalidInitialFee();
        uint256 subcollectionIdx = getSubcollectionIdxByName(subcollectionName);
        Subcollection storage subcollection = subcollections[subcollectionIdx];
        if (bytes(subcollection.params.name).length == 0) revert InvalidCollectionName();
        if (subcollection.totalMinted + mintAmount > subcollection.params.mainSupply) revert SubcollectionSoldOut();
        _checkBlacklist(to);
                        
        if (!hasRole(CLAIMER_ROLE, _msgSender())) {
            if (_totalMinted[_msgSender()][subcollectionIdx] + mintAmount > subcollection.params.maxMintPerAddress)
                revert MaxSupplyPerAddressExceeded();
            if (subcollection.totalMinted + mintAmount > subcollection.params.availableMainSupply)
                revert AvailableMainSupplyExceeded();


            uint256 initialValue = msg.value;
            uint256 discountValue = PROCESSOR.processPartnershipOperation{value: msg.value}(_msgSender(), initialFee * mintAmount, subcollectionIdx);
            initialValue += discountValue;

            bool onWhitelist = _verifyProof(
                        subcollectionName,
                        keccak256(
                            bytes.concat(keccak256(abi.encode(_msgSender(), initialValue / mintAmount)))
                        ),
                        proof
                    );

            if (subcollection.whitelistMintEnabled && subcollection.openMintEnabled) {
                if(!onWhitelist){
                   if (initialValue / mintAmount != subcollection.params.mintFee) revert InvalidMsgValue();
                }
            }
            if (subcollection.whitelistMintEnabled && !subcollection.openMintEnabled) {
                if (!onWhitelist) revert NotOnWhitelist();
            }
            if (!subcollection.whitelistMintEnabled && subcollection.openMintEnabled) {      
                if (initialValue / mintAmount != subcollection.params.mintFee) revert InvalidMsgValue();            
            }
            if (!subcollection.whitelistMintEnabled && !subcollection.openMintEnabled) {      
                revert MintNotAllowed();
            }

            (bool callSuccess, ) = incomeVault.call{value: address(this).balance}("");
            if(!callSuccess) revert EthTransferFailed();
           
        }
        
        for (uint256 i = 0; i < mintAmount; i++) {
            uint256 tokenId = _nextRandomId(
                subcollectionIdx,
                subcollection.params.mainSupply,
                subcollection.totalMinted,
                subcollection.startIndex
            );
            subcollection.totalMinted += 1;
            _totalMinted[_msgSender()][subcollectionIdx] += 1;
            _subIdByTokenId[tokenId] = subcollectionIdx;
            _safeMint(to, tokenId);
            PROCESSOR.storePartnerLinkWithTokenId(_msgSender(), tokenId);
        }
    }

    /**
     * @dev Function used to mint a golden token with a specified token ID.
     * @param subcollectionName The name of the subcollection.
     * @param goldenTicketNumbers The IDs assigned to the golden tokens being created.
     * @param to The address that will be assigned ownership of the golden token.
     */ 
    function mintGoldenToken(
        string calldata subcollectionName,
        uint256[] calldata goldenTicketNumbers,
        address to
    ) external onlyRole(CLAIMER_ROLE) {
        for (uint i = 0; i < goldenTicketNumbers.length; i++) {
            uint256 subcollectionIdx = getSubcollectionIdxByName(subcollectionName);
            if (goldenTicketNumbers[i] > subcollections[subcollectionIdx].params.goldSupply || goldenTicketNumbers[i] == 0)
                revert InvalidTokenID();
            _checkBlacklist(to);
            uint256 endIndex = subcollections[subcollectionIdx].endIndex;
            uint256 tokenId = endIndex + goldenTicketNumbers[i];
            _safeMint(to, tokenId);
            _subIdByTokenId[tokenId] = subcollectionIdx;
        } 
    }

    /**
     * @dev Withdraws ETH balance from the contract to the recipient account.
     * @param recipient The address of the recipient receiving the withdrawn ETH.
     */
    function withdraw(
        address payable recipient
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        _checkBlacklist(recipient);
        recipient.transfer(address(this).balance);
    }

    /**
     * @dev Burns a token and removes it from the collection.
     * Burn only by owner.
     * If this tokenId has associated metadata, it would be deleted after burn.
     * @param tokenId token to burn.
     */
    function burn(uint256 tokenId) external {
        uint256 subcollectionIdx = getSubcollectionIdxByTokenId(tokenId);
        bool burnEnabled = subcollections[subcollectionIdx].burnEnabled;
        if (!_isApprovedOrOwner(_msgSender(), tokenId)) revert NotTokenOwnerNorApproved();
        if (!burnEnabled) revert MintNotAllowed();
        _requireMinted(tokenId);
        _burn(tokenId);
        delete _subIdByTokenId[tokenId];
        if (bytes(_tokenCIDs[tokenId]).length != 0) {
            delete _tokenCIDs[tokenId];
        }
    }

    /**
     * @dev Sets the URI for a specific token.
     * @param tokenId The unique identifier of the token.
     * @param cid The string representing the folder's CID to be associated with the token.
     */
    function setTokenCID(
        uint256 tokenId,
        string calldata cid
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        uint256 subIdx = getSubcollectionIdxByTokenId(tokenId);
        if (subcollections[subIdx].locked) revert SubcollectionLocked();
        _tokenCIDs[tokenId] = cid;
        emit MetadataUpdate(tokenId);
    }

    /**
     * @dev Set the merkle root for verifying on-chain against the database off-chain.
     * Revert if the message is not signed by TRUSTED_SIGNER_ROLE.
     * @param subcollectionName subcollection name.
     * @param root bytes32 value of new merkle root to be set.
     */
    function setMerkleRoot(
        string calldata subcollectionName,
        bytes32 root
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        uint256 subcollectionIdx = getSubcollectionIdxByName(subcollectionName);
        subcollections[subcollectionIdx].params.merkleRoot = root;
        emit MerkleRootChanged(subcollectionName, root);
    }

    /**
     * @dev Set a new mint fee for the contract.
     * @param subcollectionName subcollection name.
     * @param newMintFee The new mint fee to be set.
     */
    function setMintFee(
        string calldata subcollectionName,
        uint256 newMintFee
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        uint256 subcollectionIdx = getSubcollectionIdxByName(subcollectionName);
        subcollections[subcollectionIdx].params.mintFee = newMintFee;
        emit MintFeeChanged(subcollectionName, newMintFee);
    }

    /**
     * @notice Sets the maximum number of tokens that can be minted by a single address.
     * @param subcollectionName subcollection name.
     * @param maxMintPerAddress New maximum number of tokens allowed per address.
     */
    function setMaxMintPerAddress(
        string calldata subcollectionName,
        uint256 maxMintPerAddress
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        uint256 subcollectionIdx = getSubcollectionIdxByName(subcollectionName);
        subcollections[subcollectionIdx].params.maxMintPerAddress = maxMintPerAddress;
        emit MaxMintPerAddressChanged(subcollectionName, maxMintPerAddress);
    }

    /**
     * @notice Set the trusted forwarder for the contract.
     * @param forwarder The address of the trusted forwarder.
     * @dev This function updates the trusted forwarder.
     */
    function setTrustedForwarder(
        address forwarder
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        if (forwarder == address(0)) revert ZeroAddress();
        _setTrustedForwarder(forwarder);
        emit TrustedForwarderChanged(forwarder);
    }

    /**
     * @dev Sets a boolean value to enable or disable the whitelist minting option.
     * @param subcollectionName subcollection name.
     * @param enabled A boolean that indicates whether or not to allow
     * addresses to be whitelisted for minting privileges.
     */
    function setWhitelistMintEnabled(
        string calldata subcollectionName,
        bool enabled
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        uint256 subcollectionIdx = getSubcollectionIdxByName(subcollectionName);
        subcollections[subcollectionIdx].whitelistMintEnabled = enabled;
        emit WhitelistMintEnabled(subcollectionName, enabled);
    }

    /**
     * @dev Sets a boolean value to enable or disable the open minting option.
     * @param subcollectionName subcollection name.
     * @param enabled A boolean that indicates the feature status.
     */
    function setOpenMintEnabled(
        string calldata subcollectionName,
        bool enabled
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        uint256 subcollectionIdx = getSubcollectionIdxByName(subcollectionName);
        subcollections[subcollectionIdx].openMintEnabled = enabled;
        emit OpenMintEnabled(subcollectionName, enabled);
    }

    /**
     * @dev Sets the locked state of a subcollection.
     * @param subcollectionName The name of the subcollection to set the locked state for.
     */
    function setSubcollectionLocked(string calldata subcollectionName) external onlyRole(TRUSTED_SIGNER_ROLE) {
        uint256 subcollectionIdx = getSubcollectionIdxByName(subcollectionName);
        subcollections[subcollectionIdx].locked = true;
        emit SubcollectionSetLocked(subcollectionName);
    }

    /**
     * @dev Sets the blacklist status for a particular address.
     * @param adrs The address to manage status of.
     * @param ban True if the address is blacklisted, false otherwise.
     */
    function setBlacklist(
        address adrs,
        bool ban
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        if (adrs == address(0)) revert ZeroAddress();
        _blacklist[adrs] = ban;
        emit BlacklistStatusChanged(adrs, ban);
    }

    /**
     * @dev Enable/Disable the burn functionality.
     * @param subcollectionName subcollection name.
     * @param enabled True if burn is enabled, false otherwise.
     */
    function setBurnEnabled(
        string calldata subcollectionName,
        bool enabled
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        uint256 subcollectionIdx = getSubcollectionIdxByName(subcollectionName);
        subcollections[subcollectionIdx].burnEnabled = enabled;
        emit BurnEnabled(subcollectionName, enabled);
    }

    function setAvailableMainSupply(
        string calldata subcollectionName,
        uint256 availableMainSupply
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        uint256 subcollectionIdx = getSubcollectionIdxByName(subcollectionName);
        subcollections[subcollectionIdx].params.availableMainSupply = availableMainSupply;
        emit AvailableMainSupplyUpdated(subcollectionName, availableMainSupply);
    }

    /**
     * @dev Sets the contract URI metadata for the NFT collection.
     * @param contractMetadataCID The URI to set as the contract metadata.
     */
    function setContractCID(
        string calldata contractMetadataCID
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        _contractMetadataCID = contractMetadataCID;
        emit ContractMetadataUpdated(contractMetadataCID);
    }

    /**
     * @dev Sets the base URL.
     * @param baseURL The URL to set.
     */
    function setBaseURL(
        string calldata baseURL
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        _baseURL = baseURL;
        emit BaseURLUpdated(baseURL);
    }

    /**
     * @dev Sets default royalty information on the contract.
     * Can only be called by an address with the TRUSTED_SIGNER_ROLE.
     * @param receiver The address of the royalty recipient.
     * @param royaltyFeesInBips The royalty fee in basis points.
     */
    function setRoyaltyInfo(
        address receiver,
        uint96 royaltyFeesInBips
    ) external onlyRole(TRUSTED_SIGNER_ROLE) {
        _setDefaultRoyalty(receiver, royaltyFeesInBips);
        emit RoyaltyInfoUpdated(receiver, royaltyFeesInBips);
    }

    /**
     * @dev Sets a new address for the income vault.
     * @param newIncomeVault The new address to be used as the income vault.
     */
    function setIncomeVault(address payable newIncomeVault) external onlyRole(TRUSTED_SIGNER_ROLE) {
        incomeVault = newIncomeVault;
        emit IncomeVaultUpdated(newIncomeVault);
    }

    /**
     * @dev Returns contract's metadata URI.
     */
    function contractURI() external view returns (string memory) {
        return string(abi.encodePacked(_baseURL, _contractMetadataCID));
    }

    /**
     * @dev Get the information of a specific Subcollection with the specified ID.
     * @param subcollectionIdx The ID of the Subcollection to get its information.
     * @return Subcollection type object that includes the information of the Subcollection.
     */
    function getSubcollection(
        uint256 subcollectionIdx
    ) external view returns (Subcollection memory) {
        return subcollections[subcollectionIdx];
    }

    /**
    * @dev Returns the total number of subcollections available.
    * @return uint256 representing the number of subcollections.
    */
    function subcollectionsCount() external view returns (uint256) {
        return subcollections.length;
    }

    /**
     * @dev Returns the subcollection ID of the given token.
     * Reverts if the token does not exist or was minted before subcollections were added.
     * @param tokenId The ID of the token to get the subcollection ID for.
     * @return The subcollection ID of the given token.
     */
    function getSubcollectionIdxByTokenId(
        uint256 tokenId
    ) public view returns (uint256) {
        _requireMinted(tokenId);
        return _subIdByTokenId[tokenId];
    }

    /**
     * @dev Looks up the ID of a subcollection by its name.
     * Reverts if the subcollection name is not found.
     * @param subcollectionName The name of the subcollection to look up.
     * @return The ID of the subcollection.
     */
    function getSubcollectionIdxByName(
        string memory subcollectionName
    ) public view returns (uint256) {
        bytes32 subcollectionNameHash = keccak256(abi.encodePacked(subcollectionName));
        uint256 subcollectionIdx = _subIdByNameHash[subcollectionNameHash];
        if (subcollections.length == 0) revert NoNestedCollections();
        if (keccak256(abi.encodePacked(subcollections[subcollectionIdx].params.name)) != subcollectionNameHash)
            revert InvalidCollection();
        return _subIdByNameHash[subcollectionNameHash];
    }

    /**
    * @dev Returns the total number of NFTs minted by a specific user for a given subcollection index.
    * @param user The address of the user for whom we want to retrieve the minted NFT count.
    * @param subcollectionIdx The index of the subcollection for which we want to retrieve the minted NFT count.
    * @return uint256 representing the total number of NFTs minted by the specified user in the specified subcollection.
    */
    function mintedBy(address user, uint256 subcollectionIdx) public view returns (uint256) {
        return _totalMinted[user][subcollectionIdx];
    }

    /**
     * @dev See {IAccessControl-supportsInterface}.
     * @dev See {IERC721-supportsInterface}.
     * @dev See {IERC2981-supportsInterface}.
     * @dev See {IERC165-supportsInterface}.
     * Checks if the contract supports an interface via its interface ID.
     * @param interfaceId The ID of the queried interface.
     * @return true if the contract implements `interfaceID`.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(IPioneersCollection, AccessControl, ERC721, ERC2981, IERC165) returns (bool) {
        return
            interfaceId == type(IAccessControl).interfaceId ||
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC2981).interfaceId ||
            interfaceId == type(IERC165).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns the uniform resource identifier (URI) for a given token.
     * Otherwise, it will use the standard ERC721 token URI composition logic to generate
     * the URI based on a base URI and a shifted token ID.
     * @param tokenId uint256 ID of the token to query.
     * @return string memory URI of the token.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override(IPioneersCollection, IERC721Metadata, ERC721) returns (string memory) {
        uint256 subcollectionIdx = getSubcollectionIdxByTokenId(tokenId);
        Subcollection storage collection = subcollections[subcollectionIdx];
        _requireMinted(tokenId);
        string memory baseCID = collection.params.baseCID;
        string memory tokenCID = _tokenCIDs[tokenId];

        tokenId = 
          subcollectionIdx == 0 
            ? tokenId 
            : tokenId - subcollections[subcollectionIdx - 1].endIndex 
                - subcollections[subcollectionIdx - 1].params.goldSupply - 1;

        if (bytes(tokenCID).length > 0) {
            return string(abi.encodePacked(_baseURL, tokenCID, "/", tokenId.toString(), ".json"));
        }

        if (bytes(collection.params.baseCID).length > 0) {
            return string(abi.encodePacked(_baseURL, baseCID, "/", tokenId.toString(), ".json"));
        }
        
    }

    /**
     * @dev Modifier that checks if the transfer is to a blacklisted address.
     * @param from The address transferring the tokens.
     * @param to The address receiving the tokens.
     * @param tokenId The ID of the token being transferred.
     * @param batchSize The number of tokens being transferred.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        _checkBlacklist(to);
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev Modifier that checks if the approval is given to a blacklisted address.
     * @param to The address being approved to transfer the tokens.
     * @param tokenId The ID of the token being approved.
     */
    function _approve(address to, uint256 tokenId) internal override {
        _checkBlacklist(to);
        super._approve(to, tokenId);
    }

    /**
     * @dev Modifier that checks if the approval is given to a blacklisted address.
     * @param owner The owner of the tokens.
     * @param operator The address being approved to operate on behalf of the owner.
     * @param approved A boolean indicating whether the operator is approved or not.
     */
    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal override {
        _checkBlacklist(operator);
        super._setApprovalForAll(owner, operator, approved);
    }

    /// @inheritdoc IERC2771Recipient
    function _msgSender()
        internal
        view
        override(Context, ERC2771Recipient)
        returns (address ret)
    {
        return ERC2771Recipient._msgSender();
    }

    /// @inheritdoc IERC2771Recipient
    function _msgData()
        internal
        view
        override(Context, ERC2771Recipient)
        returns (bytes calldata ret)
    {
        return ERC2771Recipient._msgData();
    }

    /**
     * @dev Sets the token CID for a given `tokenId`.
     * Reverts if the token does not exist. This is useful to avoid wasting gas
     * on non-existent tokens.
     * @param tokenId uint256 ID of the token to set its URI.
     * @param tokenCID string metadata CID to assign.
     */
    function _setTokenCID(uint256 tokenId, string calldata tokenCID) private {
        if (!_exists(tokenId)) revert TokenDoesNotExist();
        _tokenCIDs[tokenId] = tokenCID;
    }

    /**
     * @dev Generates a random ID for a subcollection's token.
     * @param subcollectionIdx The ID of the subcollection to mint the token for.
     * @param mainSupply The maximum number of tokens in the subcollection.
     * @param totalMinted The total number of tokens that have already been minted.
     * @param startIndex The starting tokenID for the given subcollection.
     * @return A unique, random tokenID for the subcollection.
     */
    function _nextRandomId(
        uint256 subcollectionIdx,
        uint256 mainSupply,
        uint256 totalMinted,
        uint256 startIndex
    ) private returns (uint256) {
        uint256 range = mainSupply - totalMinted;
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, subcollectionIdx))) % range;

        uint256 value = 0;
        if (_tokenMatrix[subcollectionIdx][random] == 0) {
            // If this matrix position is empty, set the value to the generated random number.
            value = random;
        } else {
            // Otherwise, use the previously stored number from the matrix.
            value = _tokenMatrix[subcollectionIdx][random];
        }

        // If the last available tokenID is still unused...
        if (_tokenMatrix[subcollectionIdx][range - 1] == 0) {
            // ...store that ID in the current matrix position.
            _tokenMatrix[subcollectionIdx][random] = range - 1;
        } else {
            // ...otherwise copy over the stored number to the current matrix position.
            _tokenMatrix[subcollectionIdx][random] = _tokenMatrix[subcollectionIdx][range - 1];
        }

        return value + startIndex;
    }

    /**
     * @dev Private function used to verify if a given leaf in a Merkle tree is valid.
     * @param subcollectionName The name of the subcollection to verify its Merkle tree.
     * @param leaf The hash of the leaf to verify on the Merkle tree.
     * @param proof The array of hashes that prove the leaf is part of the Merkle tree.
     * @return bool indicating if the proof is valid or not.
     */
    function _verifyProof(
        string calldata subcollectionName,
        bytes32 leaf,
        bytes32[] memory proof
    ) private view returns (bool) {
        uint256 subcollectionIdx = getSubcollectionIdxByName(subcollectionName);
        bytes32 collectionRoot = subcollections[subcollectionIdx].params.merkleRoot;
        return MerkleProof.verify(proof, collectionRoot, leaf);
    }

    /**
     * @dev Function used to check if an account is part of the blacklist.
     * @param account The address of the account to check.
     */
    function _checkBlacklist(address account) private view {
        if (_blacklist[account]) { 
            revert("Address is blacklisted"); 
        }
    }
}
