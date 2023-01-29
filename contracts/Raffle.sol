// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.17;
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol"; //import the random number contract.
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
error Raffle__NotEnoughEthProvided(); // error message, more gas efficient this way because we don't have to store a string, and print it.
error Raffle__TransferFailed();
error Raffle__NotOpen();
error Raffle__UpkeepNotNeeded(uint currentBalance, uint numbPLayers, uint raffleState);

/*contract is VRFConsumerBasev2 so we can use the function of that contract in this one*/
/** @title A sample Raffle contract
 *  @author Anders
 * @notice this contract is for creating a untamperable decentralized smart contract
 * @dev this impliments chainlink VRF v2 and Chainlink Automation.
 */
contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    /* Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    } // uint 0 = OPEN, 1 = CALCULATING

    /* state variables */
    uint private immutable i_enteranceFee; //private so it can only be accesed internally, (more gas efficient) imutable so it cant be changed more gas efficient.
    address payable[] private s_players; //private and payable, because we need to pay and they need to pay array.
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator; //we make this so implement the interface.
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint16 private constant REQUEST_CONFIRMARION = 3;
    uint32 private immutable i_callBackGasLimit; //
    uint32 private constant NUM_WORDS = 1;
    /* Lottery Variables */
    address private s_recentWinner;
    RaffleState private s_raffleState;
    uint private s_lastTimeStamp;
    uint private i_Interval;

    /* Events */
    event raffleEnter(address indexed player); //when this event happens, and it accepts and address, index as player.
    event RequestedRaffleWinner(uint indexed requestId);
    event WinnerPicked(address indexed winner);

    /* Functions */
    constructor(
        address vrfCoordinatorV2, //contract address we need a mog, will be formulated later.
        uint64 subscriptionId,
        bytes32 gasLane,
        uint interval,
        uint enteranceFee,
        uint32 callBackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        //takes 2 parameters, and address called vrfCoordinatorV2, and an entereance fee. the vrfCoordinatorv2 is the address that does the random number function, so we pass it that ddress.
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2); //here in the constructor we wrap it around the vrf address
        i_gasLane = gasLane;
        i_Interval = interval; //time interval used for timing the duratuion of each raffle.
        i_subscriptionId = subscriptionId;
        i_enteranceFee = enteranceFee;
        s_raffleState = RaffleState.OPEN; //set the state of raffle to be open to start with.
        s_lastTimeStamp = block.timestamp; //updates the timestamp to when the contract is deployed.
        i_callBackGasLimit = callBackGasLimit;
    }

    function enterRaffle() public payable {
        if (msg.value <= i_enteranceFee) {
            revert Raffle__NotEnoughEthProvided(); //if the amount send is less than the enterance fee, we revert the transaction with the error.
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__NotOpen();
        }
        s_players.push(payable(msg.sender)); //pushes msg.sender to the s_players array. as payable.
        //named events with the function name reversed
        emit raffleEnter(msg.sender); //trickers the event
    }

    /*
     * @dev this is the function that the chainlink automation nodes call
     *  they look for the upkeepNeeded to return true.
     * following should be true in order to return true:
     * 1. our time interval should have passed
     * 2. The lottery should have a t least 1 player, and some eth.
     * 3. our subscription should be funderd with LINK.
     * 4. Lottery should be in an "open" state
     */
    function checkUpkeep(
        //checks if it's time to update, if it's we performUpkeep
        bytes memory /*checkdata*/
    ) public view override returns (bool upkeepNeeded, bytes memory /*perfromData*/) {
        //makes us call whatever we want to check
        bool isOpen = RaffleState.OPEN == s_raffleState; //this bool wil be true as long as the RaffleState is open, and will be false, if it's in any other state
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_Interval); //checks if enough time has passed.
        bool hasPlayers = (s_players.length > 0); //true if there is more than 0 players in the players array.
        bool hasBalance = address(this).balance > 0; //checks if the contracts balance is above 0.
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance); //checks if all the bools are true in one bool, if this returns true, it's time to update, request a new number, and end the lottery.
    }

    function performUpkeep(bytes calldata /* perform data*/) external override {
        //when the Checkup function returns  true this executes
        //needs to be overrriden because it's formulated in the interface 2.
        //request random number
        //once we get it, do something with it
        (bool upkeepNeeded, ) = checkUpkeep(""); //if upkeep needed will execute. the "" is blank calldat.
        if (!upkeepNeeded) {
            //if uppdate not needed, we will revert a error.
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint(s_raffleState) //we return these values if the if statement is not met, this wat the user can see what's missing ecample, no players have entered the raffle.
            );
        }
        s_raffleState = RaffleState.CALCULATING; //updates the raffles state to calculating so no one can enter when it's in the state of finding a RandomWinner.
        uint requestId = i_vrfCoordinator.requestRandomWords( //returns an id, so we can see who request this
            i_gasLane, //gaslane, the most amount of gas you're willing to pay.
            i_subscriptionId, //subscription id which can be found in the vrf subscription details on chainlink website.
            REQUEST_CONFIRMARION, //how many confirmations the chainlink node should wait before responding.
            i_callBackGasLimit, //limit for how much computation
            NUM_WORDS //how many random numbers we want to get
        );
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(uint /*requestId*/, uint[] memory randomWords) internal override {
        //fulfill random numbers
        uint indexOfWinner = randomWords[0] % s_players.length; //takes the random word and use modulo % the length of the players array, and then the index the number it lands on is the index of the winner
        address payable recentWinner = s_players[indexOfWinner]; //sets the recentwinner to s_player at the indexOfWinner.
        s_recentWinner = recentWinner; //sets the s_recentWinner to recent winner.
        s_raffleState = RaffleState.OPEN; //opens the raffle when we have found the winner of the current raffle.
        s_players = new address payable[](0); //resets the array so we can start it new raffle, when the other one has ended. of size 0
        s_lastTimeStamp = block.timestamp; //resets the last time stamp with the current block.timestamp, so we can start a new raffle, from this block.time forward.
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(recentWinner);
    }

    function getEnteranceFee() public view returns (uint) {
        return i_enteranceFee;
    }

    function getPlayer(uint index) public view returns (address) {
        return s_players[index];
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() public pure returns (uint) {
        //pure becuase it dosen't read from storage
        return NUM_WORDS;
    }

    function getNumberOfPlayers() public view returns (uint) {
        return s_players.length;
    }

    function getLatestTimeStamp() public view returns (uint) {
        return s_lastTimeStamp;
    }

    function getRequestConfirmations() public pure returns (uint) {
        //pure because the value is hard coded, and does not read from storage.
        return REQUEST_CONFIRMARION;
    }

    function getInterval() public view returns (uint) {
        return i_Interval;
    }
}

//raffle
//enter lottery (Pay for enter some amount)
//pick a random winner (verifiably random)
//winner to be selected every x mins (automated)
//chainlink oracle -> randomness, automated execution (chain link keepers)
