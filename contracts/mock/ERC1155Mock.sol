//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract ERC1155Mock is ERC1155 {
    constructor() public ERC1155("https://api.ppw.digital/api/item/") {
        _mint(msg.sender, 1, 10, "");
    }
}
