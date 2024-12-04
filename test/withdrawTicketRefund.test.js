const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CompanyLotteries - withdrawTicketRefund", function () {
  let companyLotteries;
  let mockToken;
  let owner;
  let buyer;
  let otherUser;
  let lotteryNo;
  let snapshotId;

  const TICKET_PRICE = ethers.parseEther("10");
  const NUM_TICKETS = 32;
  const NUM_WINNERS = 5;
  const MIN_PERCENTAGE = 20;

  let randomNumber; // Variable to store the actual random number
  let randomHash;   // Variable to store the random hash generated during ticket purchase

  beforeEach(async function () {
    snapshotId = await ethers.provider.send('evm_snapshot', []);

    // Get signers
    [owner, buyer, otherUser] = await ethers.getSigners();

    // Deploy mock ERC20 token
    const MockTokenFactory = await ethers.getContractFactory("MockERC20");
    mockToken = await MockTokenFactory.deploy();

    // Deploy lottery contract
    const CompanyLotteriesFactory = await ethers.getContractFactory(
      "CompanyLotteries"
    );
    companyLotteries = await CompanyLotteriesFactory.deploy();

    // Create a lottery
    const futureTimestamp = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

    const tx = await companyLotteries
      .connect(owner)
      .createLottery(
        futureTimestamp,
        NUM_TICKETS,
        NUM_WINNERS,
        MIN_PERCENTAGE,
        TICKET_PRICE,
        ethers.encodeBytes32String("htmlhash"),
        "https://example.com"
      );

    const receipt = await tx.wait();
    const logs = receipt?.logs;
    const lotteryCreatedLog = logs?.find(
      (log) => log.fragment?.name === "LotteryCreated"
    );
    lotteryNo = lotteryCreatedLog?.args?.[0];

    // Set payment token for the lottery
    await companyLotteries.connect(owner).setPaymentToken(mockToken.target);

    // Prepare token for buyer
    await mockToken.mint(buyer.address, ethers.parseEther("1000"));
    await mockToken
      .connect(buyer)
      .approve(companyLotteries.target, ethers.parseEther("1000"));

    // Simulate ticket purchase
    const quantity = 5;
    randomNumber = Math.floor(Math.random() * 1000); // Generate a random number for testing
    randomHash = ethers.solidityPackedKeccak256(['uint'], [randomNumber]); // Generate the hash of the random number

    // Buy tickets
    await companyLotteries
      .connect(buyer)
      .buyTicketTx(lotteryNo, quantity, randomHash);

    // Prepare token for otherUser
    await mockToken.mint(otherUser.address, ethers.parseEther("1000"));
    await mockToken
      .connect(otherUser)
      .approve(companyLotteries.target, ethers.parseEther("1000"));

    // Get into the reveal phase
    await ethers.provider.send("evm_increaseTime", [1801]); // 30 minutes later
    await ethers.provider.send("evm_mine", []); // Ensure time increment

    // Now, reveal the random number using the correct random number (not hash) for buyer
    await companyLotteries
      .connect(buyer)
      .revealRndNumberTx(
        lotteryNo, // lottery no
        1, // sticket no
        5, // quantity
        randomNumber // random number
      );
  });

  afterEach(async function () {
    await ethers.provider.send("evm_revert", [snapshotId]);
  });

  describe('Successful withdrawTicketRefund', function () {
    it('should withdraw the ticket refund and emit TicketRefundWithdrawn event', async function () {
      await ethers.provider.send("evm_increaseTime", [1801]); // 30 minutes later
      await ethers.provider.send("evm_mine", []); // Ensure time increment

      // Finalize the lottery
      await companyLotteries.connect(owner).finalizeLottery(lotteryNo);

      // Get the ticket refund amount
      const tx = await companyLotteries.connect(buyer).withdrawTicketRefund(
        lotteryNo, // lottery no
        1 // sticket no
      );
      const receipt = await tx.wait();

      // Check TicketRefundWithdrawn event
      const refundEvent = receipt?.logs.find(
        (log) => log.fragment?.name === "TicketRefundWithdrawn"
      );
      expect(refundEvent).to.exist;
      expect(refundEvent?.args?.[0]).to.equal(lotteryNo);
      expect(refundEvent?.args?.[1]).to.equal(1); // sticket no
      expect(refundEvent?.args?.[2]).to.equal(buyer.address);
      expect(refundEvent?.args?.[3]).to.equal(TICKET_PRICE);
    });
  });

  describe('Failed withdrawTicketRefund', function () {
    it('should revert if the lottery does not exist', async function () {
      await expect(
        companyLotteries.connect(buyer).withdrawTicketRefund(
          999, // Non-existent lottery no
          1 // sticket no
        )
      ).to.be.revertedWith("Lottery does not exist!");
    });

    it('should revert if the lottery is not finalized or canceled', async function () {
      await expect(
        companyLotteries.connect(buyer).withdrawTicketRefund(
          lotteryNo, // lottery no
          1 // sticket no
        )
      ).to.be.revertedWith("Lottery must be finalized or canceled!");
    });

    it('should revert if the caller is not the ticket owner', async function () {
      await ethers.provider.send("evm_increaseTime", [1801]); // 30 minutes later
      await ethers.provider.send("evm_mine", []); // Ensure time increment

      // Finalize the lottery
      await companyLotteries.connect(owner).finalizeLottery(lotteryNo);

      await expect(
        companyLotteries.connect(otherUser).withdrawTicketRefund(
          lotteryNo, // lottery no
          1 // sticket no
        )
      ).to.be.revertedWith("Caller is not the ticket owner!");
    });

    it('should revert if the refund has already been withdrawn', async function () {
      await ethers.provider.send("evm_increaseTime", [1801]); // 30 minutes later
      await ethers.provider.send("evm_mine", []); // Ensure time increment

      // Finalize the lottery
      await companyLotteries.connect(owner).finalizeLottery(lotteryNo);

      // Withdraw the refund
      await companyLotteries.connect(buyer).withdrawTicketRefund(
        lotteryNo, // lottery no
        1 // sticket no
      );

      // Try to withdraw the refund again
      await expect(
        companyLotteries.connect(buyer).withdrawTicketRefund(
          lotteryNo, // lottery no
          1 // sticket no
        )
      ).to.be.revertedWith("Refund has already been withdrawn for this ticket!");
    });

    it('should revert if the refund transfer fails', async function () {
      // Set failTransfer flag to true
      await mockToken.setFailTransfer(true);

      // Finalize the lottery (assuming the lottery is active)
      await ethers.provider.send("evm_increaseTime", [1801]);
      await ethers.provider.send("evm_mine", []); // Ensure time increment
      await companyLotteries.connect(owner).finalizeLottery(lotteryNo);

      // Try to withdraw refund and expect revert
      await expect(
        companyLotteries.connect(buyer).withdrawTicketRefund(lotteryNo, 1)
      ).to.be.revertedWith("Refund transfer failed!");
    });
  });
});