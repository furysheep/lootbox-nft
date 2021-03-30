const { expect } = require('chai');

const TOKEN_ID = 1;

const delay = (ms) => new Promise((res) => setTimeout(res, ms));

describe('Auction Contract ETH flow', function () {
  let auction, nftToken;
  let owner, bidder1, bidder2, bidder3;
  it('Deploy contracts', async function () {
    [owner, bidder1, bidder2, bidder3] = await ethers.getSigners();

    const ERC1155Mock = await ethers.getContractFactory('ERC1155Mock');
    nftToken = await ERC1155Mock.deploy();
    await nftToken.deployed();

    const NFTAuctionSale = await ethers.getContractFactory('NFTAuctionSale');
    auction = await NFTAuctionSale.deploy();
    await auction.deployed();

    await nftToken.setApprovalForAll(auction.address, true);
  });

  it('Owner has minted tokens', async function () {
    expect(await nftToken.balanceOf(owner.address, 1)).to.equal(10);
  });

  it('Owner can create auction', async function () {
    const now = parseInt(Date.now() / 1000);

    await auction.createAuction(
      ethers.constants.AddressZero,
      nftToken.address,
      TOKEN_ID,
      0,
      2, // number of tokens
      now,
      now + 10
    );
  });

  it('User1 bid 1eth', async function () {
    await auction
      .connect(bidder1)
      .makeBidETH(1, { value: ethers.utils.parseEther('1.0') });
  });

  it('User2 bid 0.5eth', async function () {
    await auction
      .connect(bidder2)
      .makeBidETH(1, { value: ethers.utils.parseEther('0.5') });
  });

  it('User3 bid 2eth', async function () {
    await expect(
      auction
        .connect(bidder3)
        .makeBidETH(1, { value: ethers.utils.parseEther('2.0') })
    ).to.not.reverted;
  });

  it('User2 slipped and get back original balance', async function () {
    console.log((await bidder2.getBalance()).toString());
  });

  it('User1 and User3 in auction list', async function () {
    const bids = await auction.getBids(1);
    expect(bids[0].bidder).to.equal(bidder1.address);
    expect(bids[1].bidder).to.equal(bidder3.address);
  });

  it('User1 increase bid to 1.5eth', async function () {
    await expect(
      auction
        .connect(bidder1)
        .increaseMyBidETH(1, { value: ethers.utils.parseEther('0.5') })
    ).to.not.reverted;

    const bids = await auction.getBids(1);
    expect(bids[0].currentPrice).to.equal(ethers.utils.parseEther('1.5'));
    expect(bids[1].currentPrice).to.equal(ethers.utils.parseEther('2.0'));
  });

  it('User1 claim', async function () {
    await delay(5000);
    await auction.connect(bidder1).claimReward(1);
    expect(await nftToken.balanceOf(bidder1.address, 1)).to.equal(1);
    expect(await nftToken.balanceOf(owner.address, 1)).to.equal(9);
    await expect(auction.connect(bidder1).claimReward(1)).to.be.reverted;
  });

  it('Transfer ETH', async function () {
    const oldBalance = await owner.getBalance();
    await auction.transferETH();
    console.log(
      ethers.utils.formatEther((await owner.getBalance()).sub(oldBalance))
    );
  });
});
