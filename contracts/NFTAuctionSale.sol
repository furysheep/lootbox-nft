//SPDX-License-Identifier: Unlicense
pragma solidity ^0.6.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract NFTAuctionSale is Ownable {
    using SafeMath for uint256;

    event NewAuctionItemCreated(uint256 auctionId);
    event EmergencyStarted();
    event EmergencyStopped();
    event BidPlaced(
        uint256 auctionId,
        uint256 bidId,
        address addr,
        address transaction
    );
    event BidReplaced(
        uint256 auctionId,
        uint256 bidId,
        address addr,
        address transaction
    );
    event AuctionItemClaimed(uint256 auctionId);
    event RewardClaimed(uint256 tokenCount);
    event BidIncreased();

    struct AuctionProgress {
        uint256 currentPrice;
        address bidder;
    }

    struct Auction {
        uint256 startTime;
        uint256 endTime;
        uint256 totalSupply;
        uint256 startPrice;
        uint256 maxBidPerWallet;
        address paymentTokenAddress; // ERC20
        address auctionItemAddress; // ERC1155
        uint256 auctionItemTokenId;
        mapping(uint256 => AuctionProgress) bids;
        mapping(address => uint256) currentBids;
    }

    bool private emergencyStop = false;

    mapping(uint256 => Auction) public auctions;

    uint256 private indexOfAuction = 0;

    constructor() public {}

    function max(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a : b;
    }

    /// @notice Get max bid price in the specified auction
    /// @param auctionId Auction Id
    /// @return the max bid price
    function getMaxPrice(uint256 auctionId) public view returns (uint256) {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        Auction storage auction = auctions[auctionId];

        uint256 maxPrice = auction.bids[0].currentPrice;
        for (uint256 i = 1; i < auction.totalSupply; i++) {
            maxPrice = max(maxPrice, auction.bids[i].currentPrice);
        }

        return maxPrice;
    }

    /// @notice Get min bid price in the specified auction
    /// @param auctionId Auction Id
    /// @return the min bid price
    function getMinPrice(uint256 auctionId) public view returns (uint256) {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        Auction storage auction = auctions[auctionId];

        uint256 minPrice = auction.bids[0].currentPrice;
        for (uint256 i = 1; i < auction.totalSupply; i++) {
            minPrice = min(minPrice, auction.bids[i].currentPrice);
        }

        return minPrice;
    }

    /// @notice Transfers ERC20 tokens holding in contract to the contract owner
    /// @param tokenAddr ERC20 token address
    function transferERC20(address tokenAddr) external onlyOwner {
        IERC20 erc20 = IERC20(tokenAddr);
        erc20.transfer(_msgSender(), erc20.balanceOf(address(this)));
    }

    /// @notice Transfers ETH holding in contract to the contract owner
    function transferETH() external onlyOwner {
        _msgSender().transfer(address(this).balance);
    }

    /// @notice Create auction with specific parameters
    /// @param paymentTokenAddress ERC20 token address the bidders will pay
    /// @param paymentTokenAddress ERC1155 token address for the auction
    /// @param auctionItemTokenId Token ID of NFT
    /// @param totalSupply ERC20 token address
    /// @param startTime Auction starting time
    /// @param endTime Auction ending time
    function createAuction(
        address paymentTokenAddress,
        address auctionItemAddress,
        uint256 auctionItemTokenId,
        uint256 totalSupply,
        uint256 startTime,
        uint256 endTime
    ) external onlyOwner {
        require(emergencyStop == false, "Emergency stopped");
        require(totalSupply > 0, "Total supply should be greater than 0");
        IERC1155 auctionToken = IERC1155(auctionItemAddress);

        // check if the input address is ERC1155
        require(
            auctionToken.supportsInterface(0xd9b67a26),
            "Auction token is not ERC1155"
        );

        // check allowance
        require(
            auctionToken.isApprovedForAll(_msgSender(), address(this)),
            "Auction token has no allowance for this contract"
        );

        // Init auction struct

        // increment auction index and push
        indexOfAuction = indexOfAuction.add(1);
        auctions[indexOfAuction] = Auction(
            startTime,
            endTime,
            totalSupply,
            0,
            1,
            paymentTokenAddress,
            auctionItemAddress,
            auctionItemTokenId
        );

        // emit event
        emit NewAuctionItemCreated(indexOfAuction);
    }

    /// @notice Claim auction reward tokens to the caller
    /// @param auctionId Auction Id
    function claimReward(uint256 auctionId) external {
        require(emergencyStop == false, "Emergency stopped");
        require(auctionId <= indexOfAuction, "Auction id is invalid");

        require(
            auctions[auctionId].endTime <= block.timestamp,
            "Auction is not ended yet"
        );

        uint256 totalWon = auctions[auctionId].currentBids[_msgSender()];

        require(totalWon > 0, "Nothing to claim");

        auctions[auctionId].currentBids[_msgSender()] = 0;

        IERC1155(auctions[auctionId].auctionItemAddress).safeTransferFrom(
            owner(),
            _msgSender(),
            auctions[auctionId].auctionItemTokenId,
            totalWon,
            ""
        );

        emit RewardClaimed(totalWon);
    }

    /// @notice Increase the caller's bid price
    /// @param auctionId Auction Id
    /// @param increaseAmount The incrementing price than the original bid
    function increaseMyBid(uint256 auctionId, uint256 increaseAmount) external {
        require(emergencyStop == false, "Emergency stopped");
        require(auctionId <= indexOfAuction, "Auction id is invalid");
        require(increaseAmount > 0, "Wrong amount");
        require(
            block.timestamp < auctions[auctionId].endTime,
            "Auction is ended"
        );

        Auction storage auction = auctions[auctionId];

        uint256 count = auction.currentBids[_msgSender()];
        require(count > 0, "Not in current bids");

        IERC20(auction.paymentTokenAddress).transfer(
            address(this),
            increaseAmount * count
        );

        // Iterate currentBids and increment currentPrice
        for (uint256 i = 0; i < auction.totalSupply; i++) {
            AuctionProgress storage progress = auction.bids[i];
            if (progress.bidder == _msgSender()) {
                progress.currentPrice = progress.currentPrice.add(
                    increaseAmount
                );
            }
        }

        emit BidIncreased();
    }

    /// @notice Place bid on auction with the specified price
    /// @param auctionId Auction Id
    /// @param bidPrice ERC20 token amount
    function makeBid(uint256 auctionId, uint256 bidPrice)
        external
        isBidAvailable(auctionId)
    {
        uint256 minIndex = 0;
        uint256 minPrice = getMinPrice(auctionId);

        Auction storage auction = auctions[auctionId];
        IERC20 paymentToken = IERC20(auction.paymentTokenAddress);
        require(
            bidPrice >= auction.startPrice && bidPrice > minPrice,
            "Cannot place bid at low price"
        );

        uint256 allowance = paymentToken.allowance(_msgSender(), address(this));
        require(allowance >= bidPrice, "Check the token allowance");

        require(
            auction.currentBids[_msgSender()] < auction.maxBidPerWallet,
            "Max bid per wallet exceeded"
        );

        for (uint256 i = 0; i < auction.totalSupply; i++) {
            // Just place the bid if remaining
            if (auction.bids[i].currentPrice == 0) {
                minIndex = i;
                break;
            } else if (auction.bids[i].currentPrice == minPrice) {
                // Get last minimum price bidder
                minIndex = i;
            }
        }

        // Replace current minIndex bidder with the msg.sender
        paymentToken.transferFrom(_msgSender(), address(this), bidPrice);

        if (auction.bids[minIndex].currentPrice != 0) {
            // return previous bidders tokens
            paymentToken.transferFrom(
                address(this),
                auction.bids[minIndex].bidder,
                auction.bids[minIndex].currentPrice
            );
            auction.currentBids[auction.bids[minIndex].bidder]--;

            emit BidReplaced(
                auctionId,
                minIndex,
                auction.bids[minIndex].bidder,
                tx.origin
            );
        }

        auction.bids[minIndex].currentPrice = bidPrice;
        auction.bids[minIndex].bidder = _msgSender();

        auction.currentBids[_msgSender()] = auction.currentBids[_msgSender()]
            .add(1);

        emit BidPlaced(auctionId, minIndex, _msgSender(), tx.origin);
    }

    modifier isBidAvailable(uint256 auctionId) {
        require(
            !emergencyStop &&
                auctionId <= indexOfAuction &&
                auctions[auctionId].startTime <= block.timestamp &&
                auctions[auctionId].endTime > block.timestamp
        );
        _;
    }

    /// @notice Check the auction is finished
    /// @param auctionId Auction Id
    /// @return bool true if finished, otherwise false
    function isAuctionFinished(uint256 auctionId) external view returns (bool) {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        return (emergencyStop || auctions[auctionId].endTime < block.timestamp);
    }

    /// @notice Get remaining time for the auction
    /// @param auctionId Auction Id
    /// @return uint the remaining time for the auction
    function getTimeRemaining(uint256 auctionId)
        external
        view
        returns (uint256)
    {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        return auctions[auctionId].endTime - block.timestamp;
    }

    /// @notice Start emergency, only owner action
    function setEmergencyStart() external onlyOwner {
        emergencyStop = true;
        emit EmergencyStarted();
    }

    /// @notice Stop emergency, only owner action
    function setEmergencyStop() external onlyOwner {
        emergencyStop = false;
        emit EmergencyStopped();
    }

    /// @notice Change start time for auction
    /// @param auctionId Auction Id
    /// @param startTime new start time
    function setStartTimeForAuction(uint256 auctionId, uint256 startTime)
        external
        onlyOwner
    {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        auctions[auctionId].startTime = startTime;
    }

    /// @notice Change end time for auction
    /// @param auctionId Auction Id
    /// @param endTime new end time
    function setEndTimeForAuction(uint256 auctionId, uint256 endTime)
        external
        onlyOwner
    {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        auctions[auctionId].endTime = endTime;
    }

    /// @notice Change total supply for auction
    /// @param auctionId Auction Id
    /// @param totalSupply new Total supply
    function setTotalSupplyForAuction(uint256 auctionId, uint256 totalSupply)
        external
        onlyOwner
    {
        require(totalSupply > 0, "Total supply should be greater than 0");
        require(auctionId <= indexOfAuction, "Invalid auction id");
        auctions[auctionId].totalSupply = totalSupply;
    }

    /// @notice Change start price for auction
    /// @param auctionId Auction Id
    /// @param startPrice new Total supply
    function setStartPriceForAuction(uint256 auctionId, uint256 startPrice)
        external
        onlyOwner
    {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        auctions[auctionId].startPrice = startPrice;
    }

    /// @notice Change max bid per wallet for auction, default is 1
    /// @param auctionId Auction Id
    /// @param maxBidPerWallet Max number of bids to set
    function setMaxBidPerWalletForAuction(
        uint256 auctionId,
        uint256 maxBidPerWallet
    ) external onlyOwner {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        require(maxBidPerWallet > 0, "Should be greater than 0");
        auctions[auctionId].maxBidPerWallet = maxBidPerWallet;
    }

    /// @notice Change ERC20 token address for auction
    /// @param auctionId Auction Id
    /// @param paymentTokenAddress new ERC20 token address
    function setPaymentTokenAddressForAuction(
        uint256 auctionId,
        address paymentTokenAddress
    ) external onlyOwner {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        auctions[auctionId].paymentTokenAddress = paymentTokenAddress;
    }

    /// @notice Change auction item address for auction
    /// @param auctionId Auction Id
    /// @param auctionItemAddress new Auctioned item address
    function setAuctionItemAddress(
        uint256 auctionId,
        address auctionItemAddress
    ) external onlyOwner {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        auctions[auctionId].auctionItemAddress = auctionItemAddress;
    }

    /// @notice Change auction item token id
    /// @param auctionId Auction Id
    /// @param auctionItemTokenId new token id
    function setAuctionItemTokenId(
        uint256 auctionId,
        uint256 auctionItemTokenId
    ) external onlyOwner {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        auctions[auctionId].auctionItemTokenId = auctionItemTokenId;
    }
}
