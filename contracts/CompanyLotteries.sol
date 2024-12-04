// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CompanyLotteries is Ownable {
    struct Lottery {
        uint unixbeg;
        uint unixpurchase;
        uint unixreveal;
        uint nooftickets;
        uint noofwinners;
        uint minpercentage;
        uint ticketprice;
        bytes32 htmlhash;
        string url;
        address paymenttoken;
        uint numsold;
        uint[] winningtickets;
        mapping(address => uint[]) userTickets;
        mapping(uint => address) ticketOwner;
        mapping(uint => bytes32) ticketHashes;
        mapping(uint => bool) refundWithdrawn;
        bool isActive;
        bool proceedsWithdrawn;
    }

    struct PurchaseTx {
        uint sticketno;
        uint quantity;
    }

    uint private currentLotteryNo;
    mapping(uint => Lottery) private lotteries;

    mapping(uint => PurchaseTx[]) private purchaseTransactions;

    event LotteryCreated(
        uint lottery_no,
        uint unixbeg,
        uint nooftickets,
        uint noofwinners,
        uint minpercentage,
        uint ticketprice,
        bytes32 htmlhash,
        string url,
        address paymenttoken,
        address owner
    );

    event TicketPurchased(
        uint indexed lottery_no,
        address indexed buyer,
        uint sticketno,
        uint quantity
    );

    event TicketRefundWithdrawn(
        uint indexed lottery_no,
        uint indexed ticket_no,
        address indexed buyer,
        uint refundAmount
    );

    event ProceedsWithdrawn(
        uint indexed lottery_no,
        uint amount,
        address indexed owner
    );

    function getNumPurchaseTxs(
        uint lottery_no
    ) public view returns (uint numpurchasetxs) {
        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!");

        return purchaseTransactions[lottery_no].length;
    }

    function getIthPurchasedTicket(
        uint i,
        uint lottery_no
    ) public view returns (uint sticketno, uint quantity) {
        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!");
        require(
            i <= purchaseTransactions[lottery_no].length,
            "Index out of bounds!"
        );

        PurchaseTx storage purchaseTx = purchaseTransactions[lottery_no][i - 1];

        return (purchaseTx.sticketno, purchaseTx.quantity);
    }

    function checkIfMyTicketWon(
        uint lottery_no,
        uint ticket_no
    ) public view returns (bool won) {
        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!");
        require(
            block.timestamp > lottery.unixreveal,
            "Reveal phase has not ended yet!"
        );
        require(lottery.isActive == false, "Lottery is not finalized or canceled!");
        require(
            lottery.ticketOwner[ticket_no] != address(0),
            "Ticket does not exist or is unowned!"
        );
        require(
            lottery.ticketOwner[ticket_no] == msg.sender,
            "Ticket does not belong to the caller!"
        );

        // Check if the ticket is in the winning tickets array
        for (uint i = 0; i < lottery.winningtickets.length; i++) {
            if (lottery.winningtickets[i] == ticket_no) {
                return true; // Ticket is a winner
            }
        }

        return false; // Ticket is not a winner
    }

    function checkIfAddressTicketWon(
        address addr,
        uint lottery_no,
        uint ticket_no
    ) public view returns (bool won) {
        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!");
        require(
            block.timestamp > lottery.unixreveal,
            "Reveal phase has not ended yet!"
        );
        require(lottery.isActive == false, "Lottery is not finalized or canceled!");
        require(
            lottery.ticketOwner[ticket_no] != address(0),
            "Ticket does not exist or is unowned!"
        );
        require(
            lottery.ticketOwner[ticket_no] == addr,
            "Ticket does not belong to the address!"
        );

        // Check if the ticket is in the winning tickets array
        for (uint i = 0; i < lottery.winningtickets.length; i++) {
            if (lottery.winningtickets[i] == ticket_no) {
                return true; // Ticket is a winner
            }
        }

        return false; // Ticket is not a winner
    }

    function getIthWinningTicket(
        uint lottery_no,
        uint i
    ) public view returns (uint ticketno) {
        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!");
        require(
            block.timestamp > lottery.unixreveal,
            "Reveal phase has not ended yet!"
        );
        require(lottery.isActive == false, "Lottery is not finalized or canceled!");
        require(i < lottery.noofwinners, "Index out of bounds!");

        return lottery.winningtickets[i - 1];
    }

    function getCurrentLotteryNo() public view returns (uint) {
        return currentLotteryNo;
    }

    function getPaymentToken(
        uint lottery_no
    ) public view returns (address erctokenaddress) {
        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!");

        return lottery.paymenttoken;
    }

    function setPaymentToken(address erctokenaddress) public onlyOwner {
        require(erctokenaddress != address(0), "Invalid token address!");
        require(isContract(erctokenaddress), "Address is not a contract!");

        Lottery storage lottery = lotteries[currentLotteryNo];

        require(
            lottery.paymenttoken != erctokenaddress,
            "Token is already set!"
        );

        lottery.paymenttoken = erctokenaddress;

        emit NewPaymentTokenSet(currentLotteryNo, erctokenaddress);
    }

    event NewPaymentTokenSet(
        uint indexed lottery_no,
        address indexed paymenttoken
    );

    event LotteryCanceled(uint indexed lottery_no);

    event LotteryFinalized(uint indexed lottery_no, uint[] winners);

    constructor() Ownable() {}

    function createLottery(
        uint unixbeg,
        uint nooftickets,
        uint noofwinners,
        uint minpercentage,
        uint ticketprice,
        bytes32 htmlhash,
        string memory url
    ) public onlyOwner returns (uint lottery_no) {
        require(
            unixbeg > block.timestamp,
            "Lottery end time must be in the future!"
        );
        require(
            nooftickets > 0,
            "Number of tickets must be greater than zero!"
        );
        require(
            noofwinners > 0 && noofwinners <= nooftickets,
            "Number of winners must be greater than zero and less than or equal to number of tickets!"
        );
        require(
            minpercentage > 0 && minpercentage <= 100,
            "Minimum percentage must be greater than zero and less than or equal to 100!"
        );
        require(ticketprice > 0, "Ticket price must be greater than zero!");

        currentLotteryNo++;

        uint unixtotalpurchaseandrevealtime = unixbeg - block.timestamp;
        uint unixhalfduration = unixtotalpurchaseandrevealtime / 2;

        uint unixpurchase = block.timestamp + unixhalfduration;
        uint unixreveal = unixpurchase + unixhalfduration;

        Lottery storage lottery = lotteries[currentLotteryNo];
        lottery.unixbeg = unixbeg;
        lottery.unixpurchase = unixpurchase;
        lottery.unixreveal = unixreveal;
        lottery.nooftickets = nooftickets;
        lottery.noofwinners = noofwinners;
        lottery.minpercentage = minpercentage;
        lottery.ticketprice = ticketprice;
        lottery.htmlhash = htmlhash;
        lottery.url = url;
        lottery.isActive = true;
        lottery.proceedsWithdrawn = false;

        emit LotteryCreated(
            currentLotteryNo,
            unixbeg,
            nooftickets,
            noofwinners,
            minpercentage,
            ticketprice,
            htmlhash,
            url,
            address(0),
            owner()
        );

        return currentLotteryNo;
    }

    function buyTicketTx(
        uint lottery_no,
        uint quantity,
        bytes32 hash_rnd_number
    ) public returns (uint sticketno) {
        require(
            hash_rnd_number != bytes32(0),
            "Random hash must not be empty!"
        );

        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!");
        require(
            block.timestamp < lottery.unixpurchase,
            "Purchase phase has ended!"
        );
        require(lottery.isActive, "Lottery is not active!");
        require(
            quantity > 0 && quantity <= 30,
            "Quantity must be greater than zero and less than or equal to 30!"
        );
        require(
            lottery.numsold + quantity <= lottery.nooftickets,
            "Not enough tickets remaining!"
        );

        uint256 totalCost = quantity * lottery.ticketprice;
        // Transfer tokens from buyer to contract
        bool transferSuccess = IERC20(lottery.paymenttoken).transferFrom(
            msg.sender,
            address(this),
            totalCost
        );
        require(
            transferSuccess,
            "ERC20: transfer amount exceeds balance"
        );

        // Assign tickets
        sticketno = lottery.numsold + 1; // Starting ticket number
        for (uint i = 0; i < quantity; i++) {
            uint currentTicket = lottery.numsold + i + 1;
            lottery.ticketOwner[currentTicket] = msg.sender;
            lottery.ticketHashes[currentTicket] = hash_rnd_number;
            lottery.userTickets[msg.sender].push(currentTicket);
        }

        // Update number of tickets sold
        lottery.numsold += quantity;

        // Add transaction to the purchaseTransactions array
        purchaseTransactions[lottery_no].push(PurchaseTx(sticketno, quantity));

        // Emit an event for transparency
        emit TicketPurchased(lottery_no, msg.sender, sticketno, quantity);

        return sticketno;
    }

    function revealRndNumberTx(
        uint lottery_no,
        uint sticketno,
        uint quantity,
        uint rnd_number
    ) public {
        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!");
        require(
            block.timestamp > lottery.unixpurchase,
            "Reveal phase has not started yet!"
        );
        require(
            block.timestamp < lottery.unixreveal,
            "Reveal phase has ended!"
        );
        require(
            quantity > 0 && quantity <= 30,
            "Quantity must be greater than zero and less than or equal to 30!"
        );

        for (uint i = 0; i < quantity; i++) {
            uint currentTicket = sticketno + i;
            require(
                lottery.ticketOwner[currentTicket] == msg.sender,
                "Only the buyer can reveal the random number!"
            );
            require(
                lottery.ticketHashes[currentTicket] ==
                    keccak256(abi.encodePacked(rnd_number)),
                "Random number does not match the hash!"
            );
        }
    }

    function getLotteryInfo(
        uint lottey_no
    )
        public
        view
        returns (
            uint unixbeg,
            uint nooftickets,
            uint noofwinners,
            uint minpercentage,
            uint ticketprice
        )
    {
        Lottery storage lottery = lotteries[lottey_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!");

        return (
            lottery.unixbeg,
            lottery.nooftickets,
            lottery.noofwinners,
            lottery.minpercentage,
            lottery.ticketprice
        );
    }

    function getLotteryURL(
        uint lottery_no
    ) public view returns (bytes32 htmlhash, string memory url) {
        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!");

        return (lottery.htmlhash, lottery.url);
    }

    function getLotterySales(
        uint lottery_no
    ) public view returns (uint numsold) {
        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!");

        return lottery.numsold;
    }

    function finalizeLottery(uint lottery_no) public onlyOwner {
        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!");
        require(
            block.timestamp > lottery.unixreveal,
            "Reveal phase has not ended yet!"
        );
        require(
            lottery.isActive,
            "Lottery has already been finalized or canceled!"
        );

        uint minTicketsRequired = (lottery.nooftickets *
            lottery.minpercentage) / 100;

        if (lottery.numsold < minTicketsRequired) {
            // Cancel the lottery if minimum tickets not sold
            lottery.isActive = false;

            emit LotteryCanceled(lottery_no);
            return;
        }

        uint totalRevealedTickets = 0;
        uint[] memory revealedTickets = new uint[](lottery.numsold);

        // Collect tickets with revealed random numbers
        for (uint i = 1; i <= lottery.numsold; i++) {
            if (lottery.ticketHashes[i] != bytes32(0)) {
                revealedTickets[totalRevealedTickets] = i;
                totalRevealedTickets++;
            }
        }

        require(
            totalRevealedTickets >= lottery.noofwinners,
            "Not enough revealed tickets to select winners!"
        );

        uint[] memory winners = new uint[](lottery.noofwinners);
        uint seed = uint(
            keccak256(
                abi.encodePacked(blockhash(block.number - 1), block.timestamp)
            )
        );

        // Select unique winners
        for (uint i = 0; i < lottery.noofwinners; i++) {
            uint randomIndex = uint(keccak256(abi.encode(seed, i))) %
                totalRevealedTickets;
            winners[i] = revealedTickets[randomIndex];

            // Remove selected winner to avoid duplicates
            revealedTickets[randomIndex] = revealedTickets[
                totalRevealedTickets - 1
            ];
            totalRevealedTickets--;
        }

        // Mark the lottery as finalized and store winning tickets
        lottery.isActive = false;
        lottery.winningtickets = winners;

        emit LotteryFinalized(lottery_no, winners);
    }

    function withdrawTicketRefund(uint lottery_no, uint ticket_no) public {
        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!"); // Validate lottery exists
        require(!lottery.isActive, "Lottery must be finalized or canceled!"); // Check if the lottery is canceled
        require(lottery.ticketOwner[ticket_no] == msg.sender, "Caller is not the ticket owner!"); // Ensure the caller is the ticket owner

        require(!lottery.refundWithdrawn[ticket_no], "Refund has already been withdrawn for this ticket!"); // Check if refund was already withdrawn

        uint refundAmount = lottery.ticketprice; // Calculate refund amount
        // Transfer tokens back to the ticket owner
        bool transferSuccess = IERC20(lottery.paymenttoken).transfer(msg.sender, refundAmount);
        require(transferSuccess, "Refund transfer failed!");

        lottery.refundWithdrawn[ticket_no] = true; // Mark the ticket as refunded to prevent multiple refunds

        emit TicketRefundWithdrawn(lottery_no, ticket_no, msg.sender, refundAmount);
    }

    function withdrawTicketProceeds(uint lottery_no) public onlyOwner {
        Lottery storage lottery = lotteries[lottery_no];

        require(lottery.unixbeg != 0, "Lottery does not exist!"); // Validate lottery exists
        require(!lottery.isActive, "Lottery must be finalized or canceled!");
        require(!lottery.proceedsWithdrawn, "Proceeds have already been withdrawn!"); // Ensure proceeds haven't been withdrawn yet

        uint totalProceeds = lottery.numsold * lottery.ticketprice;

        // Transfer proceeds to the owner
        bool transferSuccess = IERC20(lottery.paymenttoken).transfer(owner(), totalProceeds);
        require(transferSuccess, "Proceeds transfer failed!");

        lottery.proceedsWithdrawn = true; // Mark proceeds as withdrawn

        emit ProceedsWithdrawn(lottery_no, totalProceeds, owner());
    }

    // Helper function to check if the address is a contract
    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}
