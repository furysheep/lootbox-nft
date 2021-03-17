const { expect } = require('chai');

const TOKEN_ID = 1;

describe('Auction Contract', function () {
  let auction, nftToken, weth;
  let owner, addr1;
  it('Deploy contracts', async function () {
    [owner, addr1] = await ethers.getSigners();

    const ERC1155Mock = await ethers.getContractFactory('ERC1155Mock');
    nftToken = await ERC1155Mock.deploy();
    await nftToken.deployed();

    const NFTAuctionSale = await ethers.getContractFactory('NFTAuctionSale');
    auction = await NFTAuctionSale.deploy();
    await auction.deployed();

    const WETH9 = await ethers.getContractFactory('WETH9');
    weth = await WETH9.deploy();
    await weth.deployed();

    await nftToken.setApprovalForAll(auction.address, true);
  });

  it('Owner has minted tokens', async function () {
    expect(await nftToken.balanceOf(owner.address, 1)).to.equal(10);
  });

  it('Owner can create auction', async function () {
    const now = Date.now();
    await auction.createAuction(
      weth.address,
      nftToken.address,
      TOKEN_ID,
      10,
      now - 60 * 1000,
      now + 60 * 1000
    );
  });
});
