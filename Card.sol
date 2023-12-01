// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";

contract Card is
    AccessControl,
    Pausable,
    ERC1155,
    ERC1155Burnable,
    ERC1155Supply,
    ERC1155URIStorage
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant SATELLITE = 1; 
    uint256 public constant PLANET = 2;
    uint256 public constant STAR = 3;
    uint256 public constant TEAM_SATELLITE = 4;
    uint256 public constant TEAM_PLANET = 5;
    uint256 public constant TEAM_STAR = 6;

    mapping(uint256 => CollectionData) public collectionDatas;

    event URIUpdated(string previousURI, string newURI);

    struct CollectionData {
        bytes32 cid;
        string uri;
    }

    constructor(string memory uri_) ERC1155(uri_) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(MINTER_ROLE, _msgSender());
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(AccessControl, ERC1155)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function uri(
        uint256 tokenId
    )
        public
        view
        virtual
        override(ERC1155, ERC1155URIStorage)
        returns (string memory)
    {
        return super.uri(tokenId);
    }

    function setBaseURI(
        string memory newURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        string memory previousURI = uri(0);
        _setBaseURI(newURI);
        emit URIUpdated(previousURI, newURI);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function mint(
        address account,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external onlyRole(MINTER_ROLE) {
        _mint(account, id, amount, data);
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external onlyRole(MINTER_ROLE) {
        _mintBatch(to, ids, amounts, data);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) whenNotPaused {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
