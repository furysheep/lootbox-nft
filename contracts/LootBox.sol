//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.7;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./RandomNumberConsumer.sol";
import "hardhat/console.sol";

contract LootBox is Ownable {
    event Deposited(
        TokenType tokenType,
        address contractAddr,
        uint256 tokenId,
        uint256 tokens
    );
    event Received(TokenType tokenType, address contractAddr, uint256 tokenId);

    using SafeMath for uint256;

    address public lootboxContractAddr;
    uint256 public lootboxTokenId;

    RandomNumberConsumer public randomGeneratorAddr;

    enum TokenType {ERC1155, ERC721}

    struct LootboxReward {
        address contractAddr;
        uint256 tokenId;
        TokenType tokenType;
        uint256 maxSupply;
        uint256 remainingSupply;
    }

    uint256 public totalAvailableSupply;
    uint256 public totalSupply;
    LootboxReward[] public rewards;

    constructor(
        address _lootboxContractAddr,
        uint256 _lootboxTokenId,
        address _randomGeneratorAddr
    ) public {
        console.log("Deploying a LootBox");
        lootboxContractAddr = _lootboxContractAddr;
        lootboxTokenId = _lootboxTokenId;
        randomGeneratorAddr = RandomNumberConsumer(_randomGeneratorAddr);
    }

    /**
     * Deposit number of tokens in reward box
     */
    function depositTokens(
        TokenType tokenType,
        address contractAddr,
        uint256 tokenId,
        uint256 tokens
    ) public onlyOwner {
        for (uint256 i = 0; i < rewards.length; i++) {
            if (
                rewards[i].tokenId == tokenId &&
                rewards[i].contractAddr == contractAddr
            ) {
                rewards[i].maxSupply = rewards[i].maxSupply.add(tokens);
                rewards[i].remainingSupply = rewards[i].remainingSupply.add(
                    tokens
                );
                totalSupply = totalSupply.add(tokens);
                totalAvailableSupply = totalAvailableSupply.add(tokens);
                return;
            }
        }
        LootboxReward memory reward =
            LootboxReward(contractAddr, tokenId, tokenType, tokens, tokens);
        rewards.push(reward);
        totalSupply = totalSupply.add(tokens);
        totalAvailableSupply = totalAvailableSupply.add(tokens);
        emit Deposited(tokenType, contractAddr, tokenId, tokens);
    }

    /**
     * Receive reward tokens while burning amount of tokens from the sender
     */
    function receiveTokens(uint256 amount) public {
        require(
            amount <= totalAvailableSupply,
            "Amount exceeds available supply"
        );
        ERC1155Burnable lootboxContract = ERC1155Burnable(lootboxContractAddr);
        require(
            lootboxContract.isApprovedForAll(msg.sender, address(this)),
            "Not approved for lootbox contract"
        );
        require(
            amount <= lootboxContract.balanceOf(msg.sender, lootboxTokenId),
            "Amount exceeds lootbox contract balance"
        );
        lootboxContract.burn(msg.sender, lootboxTokenId, amount);

        uint256 randIndex;

        for (uint256 i = 0; i < amount; i++) {
            randIndex = _rand(i);
            for (uint256 j = 0; j < rewards.length; j++) {
                if (randIndex < rewards[j].remainingSupply) {
                    if (rewards[j].tokenType == TokenType.ERC1155) {
                        ERC1155(rewards[j].contractAddr).safeTransferFrom(
                            owner(),
                            msg.sender,
                            rewards[j].tokenId,
                            1,
                            ""
                        );
                    } else {
                        ERC721(rewards[j].contractAddr).safeTransferFrom(
                            owner(),
                            msg.sender,
                            rewards[j].tokenId
                        );
                    }
                    emit Received(
                        rewards[j].tokenType,
                        rewards[j].contractAddr,
                        rewards[j].tokenId
                    );
                    rewards[j].remainingSupply = rewards[j].remainingSupply.sub(
                        1
                    );
                    break;
                } else {
                    randIndex = randIndex.sub(rewards[j].remainingSupply);
                }
            }
            totalAvailableSupply = totalAvailableSupply.sub(1);
        }
    }

    /**
     @notice Generate unpredictable random number
     */
    function _rand(uint256 offset) public view returns (uint256) {
        uint256 random = randomGeneratorAddr.getRandomResult();
        uint256 seed =
            uint256(
                keccak256(
                    abi.encodePacked(
                        random +
                            block.timestamp +
                            block.difficulty +
                            ((
                                uint256(
                                    keccak256(abi.encodePacked(block.coinbase))
                                )
                            ) / (block.timestamp - offset * block.difficulty)) +
                            block.gaslimit +
                            ((
                                uint256(keccak256(abi.encodePacked(msg.sender)))
                            ) / (block.timestamp + offset * block.number)) +
                            block.number
                    )
                )
            );
        return
            seed.sub(seed.div(totalAvailableSupply).mul(totalAvailableSupply));
    }
}
