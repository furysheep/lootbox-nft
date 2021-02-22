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

    bool public emergencyStop = false;
    address public salesPerson = owner();

    mapping(uint256 => Auction) public auctions;

    uint256 public indexOfAuction = 0;

    constructor() public {}

    function max(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a : b;
    }

    function getMaxPrice(uint256 auctionId) public view returns (uint256) {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        Auction storage auction = auctions[auctionId];

        uint256 maxPrice = auction.bids[0].currentPrice;
        for (uint256 i = 1; i < auction.totalSupply; i++) {
            maxPrice = max(maxPrice, auction.bids[i].currentPrice);
        }

        return maxPrice;
    }

    function getMinPrice(uint256 auctionId) public view returns (uint256) {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        Auction storage auction = auctions[auctionId];

        uint256 minPrice = auction.bids[0].currentPrice;
        for (uint256 i = 1; i < auction.totalSupply; i++) {
            minPrice = min(minPrice, auction.bids[i].currentPrice);
        }

        return minPrice;
    }

    function claimERC20Tokens(address tokenAddr) public onlyOwner {
        IERC20(tokenAddr).transferFrom(
            address(this),
            owner(),
            IERC20(tokenAddr).balanceOf(address(this))
        );
    }

    function createAuction(
        address paymentTokenAddress,
        address auctionItemAddress,
        uint256 auctionItemTokenId,
        uint256 totalSupply,
        uint256 startTime,
        uint256 endTime
    ) public {
        require(totalSupply > 0, "Total supply is 0");
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

    function claimReward(uint256 auctionId) external {
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

    function increaseMyBid(uint256 auctionId, uint256 increaseAmount) public {
        require(auctionId <= indexOfAuction, "Auction id is invalid");
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

    function makeBid(uint256 auctionId, uint256 bidPrice)
        public
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
                auctions[auctionId].startTime >= block.timestamp &&
                auctions[auctionId].endTime < block.timestamp
        );
        _;
    }

    function isAuctionFinished(uint256 auctionId) public view returns (bool) {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        return (emergencyStop || auctions[auctionId].endTime < block.timestamp);
    }

    function getTimeRemaining(uint256 auctionId) public view returns (uint256) {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        return auctions[auctionId].endTime - block.timestamp;
    }

    function setEmergencyStart() public onlyOwner {
        emergencyStop = true;
        emit EmergencyStarted();
    }

    function setEmergencyStop() public onlyOwner {
        emergencyStop = false;
        emit EmergencyStopped();
    }

    function setMaxBidPerWallet(uint256 auctionId, uint256 maxBidPerWallet)
        public
        onlyOwner
    {
        require(auctionId <= indexOfAuction, "Invalid auction id");
        auctions[auctionId].maxBidPerWallet = maxBidPerWallet;
    }
}
