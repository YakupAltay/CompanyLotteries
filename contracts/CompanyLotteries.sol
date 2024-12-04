// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
		bool isFinalized;
		bool isCanceled;
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

	// Function to get the number of purchase transactions for a specific lottery
	function getNumPurchaseTxs(
		uint lottery_no  // The lottery number for which we want to retrieve the number of purchase transactions
	) public view returns (uint numpurchasetxs) {
		// Retrieve the lottery data using the provided lottery number
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure that the specified lottery exists by checking the start time
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Return the number of purchase transactions for the specified lottery
		return purchaseTransactions[lottery_no].length;
	}

	// Function to get the ith purchased ticket and its quantity from a specific lottery
	function getIthPurchasedTicket(
		uint i,             // The index of the purchase transaction (1-based index)
		uint lottery_no     // The lottery number from which the ticket was purchased
	) public view returns (uint sticketno, uint quantity) {
		// Retrieve the lottery data using the provided lottery number
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure the specified lottery exists by checking the start time
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Ensure the provided index is within the bounds of the purchase transactions array
		require(
			i <= purchaseTransactions[lottery_no].length,
			"Index out of bounds!"
		);

		// Retrieve the purchase transaction at the specified index (1-based index, so we subtract 1)
		PurchaseTx storage purchaseTx = purchaseTransactions[lottery_no][i - 1];

		// Return the ticket number and quantity from the purchase transaction
		return (purchaseTx.sticketno, purchaseTx.quantity);
	}

	// Function to check if the caller's ticket has won in the specified lottery
	function checkIfMyTicketWon(
		uint lottery_no,  // Lottery number
		uint ticket_no    // Ticket number to check
	) public view returns (bool won) {
		// Retrieve the lottery data using the provided lottery number
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure the specified lottery exists (check if the start time is valid)
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Ensure the reveal phase has ended before querying the result
		require(
			block.timestamp > lottery.unixreveal,
			"Reveal phase has not ended yet!"
		);

		// Ensure the lottery has been finalized or canceled (i.e., no active lottery)
		require(lottery.isActive == false, "Lottery is not finalized or canceled!");

		// Ensure the ticket exists and is owned by the caller (the sender of the transaction)
		require(
			lottery.ticketOwner[ticket_no] != address(0),
			"Ticket does not exist or is unowned!"
		);
		require(
			lottery.ticketOwner[ticket_no] == msg.sender,
			"Ticket does not belong to the caller!"
		);

		// Check if the ticket is present in the list of winning tickets
		for (uint i = 0; i < lottery.winningtickets.length; i++) {
			if (lottery.winningtickets[i] == ticket_no) {
				return true; // Ticket is a winner
			}
		}

		// Return false if the ticket is not in the list of winners
		return false; // Ticket is not a winner
	}

	// Function to check if the specified address owns a winning ticket in the specified lottery
	function checkIfAddressTicketWon(
		address addr,  // Address of the ticket holder
		uint lottery_no, // Lottery number
		uint ticket_no  // Ticket number to check
	) public view returns (bool won) {
		// Retrieve the lottery data using the provided lottery number
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure the specified lottery exists (check if the start time is valid)
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Ensure the reveal phase has ended before querying the result
		require(
			block.timestamp > lottery.unixreveal,
			"Reveal phase has not ended yet!"
		);

		// Ensure the lottery has been finalized or canceled (i.e., no active lottery)
		require(lottery.isActive == false, "Lottery is not finalized or canceled!");

		// Ensure the ticket exists and is owned by the specified address
		require(
			lottery.ticketOwner[ticket_no] != address(0),
			"Ticket does not exist or is unowned!"
		);
		require(
			lottery.ticketOwner[ticket_no] == addr,
			"Ticket does not belong to the address!"
		);

		// Check if the ticket is present in the list of winning tickets
		for (uint i = 0; i < lottery.winningtickets.length; i++) {
			if (lottery.winningtickets[i] == ticket_no) {
				return true; // Ticket is a winner
			}
		}

		// Return false if the ticket is not in the list of winners
		return false; // Ticket is not a winner
	}

	// Function to retrieve the ith winning ticket number for a given lottery
	function getIthWinningTicket(
		uint lottery_no,
		uint i
	) public view returns (uint ticketno) {
		// Retrieve the lottery information based on the provided lottery number
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure the lottery exists (check if the start time is valid)
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Ensure the reveal phase has ended before querying the winning ticket
		require(
			block.timestamp > lottery.unixreveal,
			"Reveal phase has not ended yet!"
		);

		// Ensure the lottery has been finalized or canceled (no active lottery)
		require(lottery.isActive == false, "Lottery is not finalized or canceled!");

		// Ensure the index is within bounds for the list of winners
		require(i < lottery.noofwinners, "Index out of bounds!");

		// Return the ith winning ticket number (index starts from 0)
		return lottery.winningtickets[i - 1];
	}

	// Function to retrieve the current active lottery number
	function getCurrentLotteryNo() public view returns (uint) {
		// Return the current lottery number (this is a global variable that tracks the latest created lottery)
		return currentLotteryNo;
	}

	// Function to retrieve the payment token address for a given lottery
	function getPaymentToken(
		uint lottery_no
	) public view returns (address erctokenaddress) {
		// Retrieve the lottery data for the given lottery number
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure that the lottery exists by checking if the 'unixbeg' timestamp is non-zero
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Return the payment token address associated with the lottery
		return lottery.paymenttoken;
	}

	// Function to set a new ERC20 token as the payment token for the current lottery
	function setPaymentToken(address erctokenaddress) public onlyOwner {
		// Ensure the provided address is not zero (invalid address)
		require(erctokenaddress != address(0), "Invalid token address!");

		// Ensure the provided address is a contract (ERC20 token contract)
		require(isContract(erctokenaddress), "Address is not a contract!");

		// Retrieve the current lottery based on the lottery number
		Lottery storage lottery = lotteries[currentLotteryNo];

		// Ensure the payment token is not already set to the provided address
		require(
			lottery.paymenttoken != erctokenaddress,
			"Token is already set!"
		);

		// Set the payment token for the lottery
		lottery.paymenttoken = erctokenaddress;

		// Emit an event to log the new payment token set for the lottery
		emit NewPaymentTokenSet(currentLotteryNo, erctokenaddress);
	}

    event NewPaymentTokenSet(
        uint indexed lottery_no,
        address indexed paymenttoken
    );

    event LotteryCanceled(uint indexed lottery_no);

    event LotteryFinalized(uint indexed lottery_no, uint[] winners);

    constructor() Ownable() {}

	// Function to create a new lottery
	function createLottery(
		uint unixbeg,             // The beginning time for the lottery (Unix timestamp)
		uint nooftickets,        // The total number of tickets for the lottery
		uint noofwinners,        // The number of winners for the lottery
		uint minpercentage,      // The minimum percentage of tickets that must be sold
		uint ticketprice,        // The price of one ticket
		bytes32 htmlhash,        // The hash of the HTML file (could be a metadata URL or similar)
		string memory url        // The URL related to the lottery (e.g., lottery's landing page)
	) public onlyOwner returns (uint lottery_no) { // Only the owner can create the lottery

		// Ensure the lottery's end time is in the future
		require(
			unixbeg > block.timestamp,
			"Lottery end time must be in the future!"
		);

		// Ensure the number of tickets is greater than zero
		require(
			nooftickets > 0,
			"Number of tickets must be greater than zero!"
		);

		// Ensure the number of winners is valid (greater than zero and less than or equal to the number of tickets)
		require(
			noofwinners > 0 && noofwinners <= nooftickets,
			"Number of winners must be greater than zero and less than or equal to number of tickets!"
		);

		// Ensure the minimum percentage is valid (greater than zero and less than or equal to 100)
		require(
			minpercentage > 0 && minpercentage <= 100,
			"Minimum percentage must be greater than zero and less than or equal to 100!"
		);

		// Ensure the ticket price is greater than zero
		require(ticketprice > 0, "Ticket price must be greater than zero!");

		// Increment the lottery number (ID) for the new lottery
		currentLotteryNo++;

		// Calculate the duration for the purchase and reveal phases
		uint unixtotalpurchaseandrevealtime = unixbeg - block.timestamp;
		uint unixhalfduration = unixtotalpurchaseandrevealtime / 2;

		// Set the purchase phase end time (half of the total time)
		uint unixpurchase = block.timestamp + unixhalfduration;

		// Set the reveal phase end time (half of the total time after purchase)
		uint unixreveal = unixpurchase + unixhalfduration;

		// Set the lottery details in the `lotteries` mapping for the current lottery
		Lottery storage lottery = lotteries[currentLotteryNo];
		lottery.unixbeg = unixbeg;                       // Set the beginning time of the lottery
		lottery.unixpurchase = unixpurchase;             // Set the purchase phase end time
		lottery.unixreveal = unixreveal;                 // Set the reveal phase end time
		lottery.nooftickets = nooftickets;               // Set the total number of tickets
		lottery.noofwinners = noofwinners;               // Set the number of winners
		lottery.minpercentage = minpercentage;           // Set the minimum percentage of tickets needed for success
		lottery.ticketprice = ticketprice;               // Set the price of each ticket
		lottery.htmlhash = htmlhash;                     // Set the hash of the HTML file
		lottery.url = url;                               // Set the URL related to the lottery
		lottery.isActive = true;                         // Mark the lottery as active
		lottery.proceedsWithdrawn = false;               // Set proceeds withdrawal status to false initially

		// Emit the LotteryCreated event to notify about the new lottery
		emit LotteryCreated(
			currentLotteryNo,  // The ID of the created lottery
			unixbeg,            // The lottery's start time
			nooftickets,        // The total number of tickets
			noofwinners,        // The number of winners
			minpercentage,      // The minimum percentage of tickets sold
			ticketprice,        // The price of each ticket
			htmlhash,           // The hash of the HTML file
			url,                // The URL of the lottery
			address(0),         // The payment token (initially not set)
			owner()             // The owner address
		);

		// Return the ID of the newly created lottery
		return currentLotteryNo;
	}

    // Function to allow users to buy tickets for a specific lottery
	function buyTicketTx(
		uint lottery_no,          // The ID of the lottery
		uint quantity,            // The number of tickets the user wants to buy
		bytes32 hash_rnd_number   // The hash of the random number for the ticket
	) public returns (uint sticketno) {  // Returns the starting ticket number

		// Ensure that the random hash is not empty
		require(
			hash_rnd_number != bytes32(0),
			"Random hash must not be empty!"
		);

		// Retrieve the lottery data from the mapping using the lottery ID
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure that the lottery exists (its start time must be set)
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Ensure that the purchase phase is still open (current time should be before the purchase end time)
		require(
			block.timestamp < lottery.unixpurchase,
			"Purchase phase has ended!"
		);

		// Ensure that the lottery is still active
		require(lottery.isActive, "Lottery is not active!");

		// Ensure that the quantity of tickets is within the allowable range (between 1 and 30)
		require(
			quantity > 0 && quantity <= 30,
			"Quantity must be greater than zero and less than or equal to 30!"
		);

		// Ensure that there are enough tickets remaining to complete the purchase
		require(
			lottery.numsold + quantity <= lottery.nooftickets,
			"Not enough tickets remaining!"
		);

		// Calculate the total cost of the tickets being purchased
		uint256 totalCost = quantity * lottery.ticketprice;

		// Transfer the total ticket price from the buyer to the lottery contract (ERC20 transfer)
		bool transferSuccess = IERC20(lottery.paymenttoken).transferFrom(
			msg.sender,             // The sender (buyer)
			address(this),          // The recipient (the lottery contract)
			totalCost               // The total amount to transfer
		);

		// Ensure that the transfer was successful
		require(
			transferSuccess,
			"ERC20: transfer amount exceeds balance"
		);

		// Assign tickets to the buyer
		sticketno = lottery.numsold + 1;  // The starting ticket number for the buyer
		for (uint i = 0; i < quantity; i++) {
			uint currentTicket = lottery.numsold + i + 1;  // The current ticket number
			lottery.ticketOwner[currentTicket] = msg.sender; // Assign the ticket to the buyer
			lottery.ticketHashes[currentTicket] = hash_rnd_number;  // Assign the random hash to the ticket
			lottery.userTickets[msg.sender].push(currentTicket);  // Add the ticket to the buyer's tickets array
		}

		// Update the total number of tickets sold
		lottery.numsold += quantity;

		// Add the purchase transaction to the transaction history for this lottery
		purchaseTransactions[lottery_no].push(PurchaseTx(sticketno, quantity));

		// Emit the TicketPurchased event to notify about the ticket purchase
		emit TicketPurchased(lottery_no, msg.sender, sticketno, quantity);

		// Return the starting ticket number for the purchased tickets
		return sticketno;
	}

	// Function to reveal the random number for the buyer's tickets
	function revealRndNumberTx(
		uint lottery_no,       // The ID of the lottery
		uint sticketno,        // The starting ticket number
		uint quantity,         // The number of tickets the buyer wants to reveal
		uint rnd_number        // The actual random number that the buyer wants to reveal
	) public {  // No return value; the function is intended to just reveal the number

		// Retrieve the lottery data from the mapping using the lottery ID
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure that the lottery exists (its start time must be set)
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Ensure that the reveal phase has started (current time must be after the purchase phase)
		require(
			block.timestamp > lottery.unixpurchase,
			"Reveal phase has not started yet!"
		);

		// Ensure that the reveal phase has not ended (current time must be before the reveal end time)
		require(
			block.timestamp < lottery.unixreveal,
			"Reveal phase has ended!"
		);

		// Ensure that the quantity of tickets to be revealed is within the allowable range (between 1 and 30)
		require(
			quantity > 0 && quantity <= 30,
			"Quantity must be greater than zero and less than or equal to 30!"
		);

		// Loop through the tickets to verify each ticket
		for (uint i = 0; i < quantity; i++) {
			uint currentTicket = sticketno + i;  // Get the current ticket number

			// Ensure that the ticket belongs to the buyer (only the buyer can reveal the number)
			require(
				lottery.ticketOwner[currentTicket] == msg.sender,
				"Only the buyer can reveal the random number!"
			);

			// Ensure that the provided random number matches the stored hash for the ticket
			require(
				lottery.ticketHashes[currentTicket] ==
					keccak256(abi.encodePacked(rnd_number)), // Hash the revealed random number to match the stored hash
				"Random number does not match the hash!"
			);
		}

		// If all checks pass, the random number is successfully revealed
		// The function does not explicitly emit an event or return a value,
		// but other actions could follow this check, such as storing results or emitting events.
	}

	// Function to get the information of a specific lottery
	function getLotteryInfo(
		uint lottey_no  // The ID of the lottery to retrieve information for
	)
		public
		view
		returns (
			uint unixbeg,         // The starting time of the lottery
			uint nooftickets,     // The number of tickets available for the lottery
			uint noofwinners,     // The number of winners for the lottery
			uint minpercentage,   // The minimum percentage of tickets that must be sold for the lottery to proceed
			uint ticketprice      // The price of a single ticket
		)
	{
		// Retrieve the lottery data from the mapping using the lottery ID
		Lottery storage lottery = lotteries[lottey_no];

		// Ensure that the lottery exists (check if unixbeg is set)
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Return the details of the lottery
		return (
			lottery.unixbeg,       // The starting time of the lottery
			lottery.nooftickets,   // The total number of tickets available for purchase
			lottery.noofwinners,   // The number of winners
			lottery.minpercentage, // The minimum percentage of tickets required for the lottery to proceed
			lottery.ticketprice    // The price of a single ticket
		);
	}

	// Function to get the HTML hash and URL of a specific lottery
	function getLotteryURL(
		uint lottery_no  // The ID of the lottery to retrieve the URL and HTML hash for
	)
		public
		view
		returns (bytes32 htmlhash, string memory url)  // The HTML hash and URL associated with the lottery
	{
		// Retrieve the lottery data from the lotteries mapping using the provided lottery ID
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure that the lottery exists (check if unixbeg is set)
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Return the HTML hash and URL for the lottery
		return (lottery.htmlhash, lottery.url);
	}

	// Function to get the number of tickets sold in a specific lottery
	function getLotterySales(
		uint lottery_no  // The ID of the lottery to retrieve the sales data for
	)
		public
		view
		returns (uint numsold)  // The number of tickets sold for the lottery
	{
		// Retrieve the lottery data from the lotteries mapping using the provided lottery ID
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure that the lottery exists (check if unixbeg is set)
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Return the number of tickets sold for the lottery
		return lottery.numsold;
	}

    // Function to finalize a lottery, selecting winners if the lottery has met the minimum ticket sales
	function finalizeLottery(uint lottery_no) public onlyOwner {
		// Retrieve the lottery details from the lotteries mapping
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure the lottery exists (check if unixbeg is set)
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Ensure the reveal phase has ended (check if current time is past the reveal phase)
		require(block.timestamp > lottery.unixreveal, "Reveal phase has not ended yet!");

		// Ensure the lottery is active and not already finalized or canceled
		require(lottery.isActive, "Lottery has already been finalized or canceled!");

		// Calculate the minimum number of tickets required to proceed with the lottery
		uint minTicketsRequired = (lottery.nooftickets * lottery.minpercentage) / 100;

		// If the number of tickets sold is less than the minimum required, cancel the lottery
		if (lottery.numsold < minTicketsRequired) {
			// Mark the lottery as inactive
			lottery.isActive = false;

			// Mark the lottery as canceled
			lottery.isCanceled = true;

			// Emit a 'LotteryCanceled' event to notify listeners
			emit LotteryCanceled(lottery_no);
			return;
		}

		uint totalRevealedTickets = 0;
		uint[] memory revealedTickets = new uint[](lottery.numsold);

		// Collect tickets that have revealed random numbers
		for (uint i = 1; i <= lottery.numsold; i++) {
			if (lottery.ticketHashes[i] != bytes32(0)) {
				revealedTickets[totalRevealedTickets] = i;
				totalRevealedTickets++;
			}
		}

		// Ensure there are enough revealed tickets to select winners
		require(
			totalRevealedTickets >= lottery.noofwinners,
			"Not enough revealed tickets to select winners!"
		);

		uint[] memory winners = new uint[](lottery.noofwinners);

		// Generate a random seed using the block hash and the current timestamp
		uint seed = uint(
			keccak256(
				abi.encodePacked(blockhash(block.number - 1), block.timestamp)
			)
		);

		// Select unique winners using the random seed
		for (uint i = 0; i < lottery.noofwinners; i++) {
			uint randomIndex = uint(keccak256(abi.encode(seed, i))) %
				totalRevealedTickets;
			winners[i] = revealedTickets[randomIndex];

			// Remove the selected winner from the list to avoid duplicates
			revealedTickets[randomIndex] = revealedTickets[
				totalRevealedTickets - 1
			];
			totalRevealedTickets--;
		}

		// Mark the lottery as finalized and store the winning tickets
		lottery.isActive = false;
		lottery.isFinalized = true;
		lottery.winningtickets = winners;

		// Emit the 'LotteryFinalized' event to notify listeners
		emit LotteryFinalized(lottery_no, winners);
	}

    // Function to withdraw the ticket refund
	function withdrawTicketRefund(uint lottery_no, uint ticket_no) public {
		// Retrieve the specific lottery from the mapping
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure the lottery exists (check if unixbeg is set)
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Ensure the lottery is finalized or canceled (check if isActive is false)
		require(!lottery.isActive, "Lottery must be finalized or canceled!");

		// Ensure the lottery is canceled
		require(lottery.isCanceled, "Lottery must be canceled!");

		// Ensure the caller is the owner of the ticket
		require(lottery.ticketOwner[ticket_no] == msg.sender, "Caller is not the ticket owner!");

		// Ensure the refund has not already been withdrawn for this ticket
		require(!lottery.refundWithdrawn[ticket_no], "Refund has already been withdrawn for this ticket!");

		// Calculate the refund amount (ticket price)
		uint refundAmount = lottery.ticketprice;

		// Transfer the refund amount to the ticket owner
		bool transferSuccess = IERC20(lottery.paymenttoken).transfer(msg.sender, refundAmount);
		require(transferSuccess, "Refund transfer failed!");

		// Mark the ticket as refunded to prevent multiple refunds
		lottery.refundWithdrawn[ticket_no] = true;

		// Emit an event for transparency
		emit TicketRefundWithdrawn(lottery_no, ticket_no, msg.sender, refundAmount);
	}

    // Function to withdraw the proceeds from the lottery after it has been finalized
	function withdrawTicketProceeds(uint lottery_no) public onlyOwner {
		// Retrieve the specific lottery from the mapping
		Lottery storage lottery = lotteries[lottery_no];

		// Ensure the lottery exists (check if unixbeg is set)
		require(lottery.unixbeg != 0, "Lottery does not exist!");

		// Ensure the lottery is finalized or canceled (check if isActive is false)
		require(!lottery.isActive, "Lottery must be finalized or canceled!");

		// Ensure the proceeds have not already been withdrawn
		require(!lottery.proceedsWithdrawn, "Proceeds have already been withdrawn!");

		// Calculate the total proceeds (number of tickets sold * ticket price)
		uint totalProceeds = lottery.numsold * lottery.ticketprice;

		// Transfer the proceeds to the owner (payment token transfer)
		bool transferSuccess = IERC20(lottery.paymenttoken).transfer(owner(), totalProceeds);
		require(transferSuccess, "Proceeds transfer failed!");

		// Mark the proceeds as withdrawn to prevent multiple withdrawals
		lottery.proceedsWithdrawn = true;

		// Emit an event for transparency (ProceedsWithdrawn event)
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
