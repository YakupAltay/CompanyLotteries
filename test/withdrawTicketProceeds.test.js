const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CompanyLotteries - withdrawTicketProceeds", function () {
  let companyLotteries;
  let mockToken;
  let owner;
  let buyer;
  let otherUser;
  let lotteryNo;
  let snapshotId;
  let quantity;
  let quantity2;

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
    quantity = 5;
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

    // Simulate ticket purchase
    quantity2 = 5;
    const randomNumber2 = Math.floor(Math.random() * 1000); // Generate a random number for testing
    const randomHash2 = ethers.solidityPackedKeccak256(['uint'], [randomNumber2]); // Generate the hash of the random number

    // Buy tickets
    await companyLotteries
      .connect(otherUser)
      .buyTicketTx(lotteryNo, quantity2, randomHash2);

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

    // Now, reveal the random number using the correct random number (not hash) for otherUser
    await companyLotteries
      .connect(otherUser)
      .revealRndNumberTx(
        lotteryNo, // lottery no
        6, // sticket no
        5, // quantity
        randomNumber2 // random number
      );
  });

  afterEach(async function () {
    await ethers.provider.send("evm_revert", [snapshotId]);
  });

  describe('Successful withdrawTicketProceeds', function () {
    it('should withdraw the ticket proceeds and emit ProceedsWithdrawn event', async function () {
      await ethers.provider.send("evm_increaseTime", [1801]); // 30 minutes later
      await ethers.provider.send("evm_mine", []); // Ensure time increment

      // Finalize the lottery
      await companyLotteries.connect(owner).finalizeLottery(lotteryNo);

      // Calculate the total proceeds
      const totalTickets = quantity + quantity2; // Total tickets sold
      const totalProceeds = ethers.parseUnits((totalTickets * 10).toString(), "ether");  // Calculate total proceeds in the correct unit

      // Withdraw the ticket proceeds
      const tx = await companyLotteries.connect(owner).withdrawTicketProceeds(lotteryNo);
      const receipt = await tx.wait();

      // Check ProceedsWithdrawn event
      const proceedsEvent = receipt?.logs.find(
        (log) => log.fragment?.name === "ProceedsWithdrawn"
      );

      expect(proceedsEvent).to.exist;
      expect(proceedsEvent?.args?.[0]).to.equal(lotteryNo);
      expect(proceedsEvent?.args?.[1]).to.equal(totalProceeds);  // Compare BigNumber to BigNumber directly
      expect(proceedsEvent?.args?.[2]).to.equal(owner.address);

      // Verify token transfer
      const finalBalance = await mockToken.balanceOf(owner.address);
      expect(finalBalance).to.equal(totalProceeds);  // Verify the balance equals the total proceeds
    });
  });

  describe('Failed withdrawTicketProceeds', function () {
    it('should revert if the lottery does not exist', async function () {
      await expect(
        companyLotteries
          .connect(owner)
          .withdrawTicketProceeds(999)
      ).to.be.revertedWith("Lottery does not exist!");
    });

    it('should revert if the lottery is not finalized or canceled', async function () {
      await expect(
        companyLotteries
          .connect(owner)
          .withdrawTicketProceeds(lotteryNo)
      ).to.be.revertedWith("Lottery must be finalized or canceled!");
    });

    it('should revert if the caller is not the owner', async function () {
      await ethers.provider.send("evm_increaseTime", [1801]); // Fast forward past the lottery end time
      await ethers.provider.send("evm_mine", []); // Ensure time increment

      await companyLotteries
        .connect(owner)
        .finalizeLottery(lotteryNo);

      await expect(
        companyLotteries
          .connect(buyer)
          .withdrawTicketProceeds(lotteryNo)
      ).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it('should revert if the ticket proceeds have already been withdrawn', async function () {
      await ethers.provider.send("evm_increaseTime", [1801]); // Fast forward past the lottery end time
      await ethers.provider.send("evm_mine", []); // Ensure time increment

      await companyLotteries
        .connect(owner)
        .finalizeLottery(lotteryNo);

      await companyLotteries
        .connect(owner)
        .withdrawTicketProceeds(lotteryNo);

      await expect(
        companyLotteries
          .connect(owner)
          .withdrawTicketProceeds(lotteryNo)
      ).to.be.revertedWith("Proceeds have already been withdrawn!");
    });

    it('should revert if the proceeds transfer fails', async function () {
      // Set failTransfer flag to true
      await mockToken.setFailTransfer(true);

      // Finalize the lottery (assuming the lottery is active)
      await ethers.provider.send("evm_increaseTime", [1801]);
      await ethers.provider.send("evm_mine", []); // Ensure time increment
      await companyLotteries.connect(owner).finalizeLottery(lotteryNo);

      // Try to withdraw refund and expect revert
      await expect(
        companyLotteries.connect(owner).withdrawTicketProceeds(lotteryNo)
      ).to.be.revertedWith("Refund transfer failed!");
    });
  });
});
