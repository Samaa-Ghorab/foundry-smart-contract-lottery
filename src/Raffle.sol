// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// NOTES:
// It's much more gas efficient to revert early than to do a bunch of computation and then revert later
// events like emitting shouldn't be put after interactions because there are some interactions that can change the value of storage variables so you might emit a wrong value

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title A sample Raffle contract
 * @author Samaa Ghorab
 * @notice This contract is for creating a sample raffle contract
 * @dev Implements Chainlink VRFv2
 */
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract Raffle is VRFConsumerBaseV2Plus {
    /**
     * Errors
     */
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);
    /*
    * Type Declarations
     */

    enum RaffleState { //each state can be converted into integers
        OPEN, //0
        CALCULATING //1

    }

    /**
     * State Variables
     */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable I_ENTRANCE_FEE;
    //@dev Duration of the lottery in seconds
    uint256 private immutable I_INTERVAL;
    // VRFConsumerBaseV2Plus private immutable I_VRF_COORDINATOR;
    bytes32 private immutable I_KEY_HASH;
    uint256 private immutable I_SUBSCRIPTION_ID;
    uint32 private immutable I_CALLBACK_GAS_LIMIT;
    address payable[] private sPlayers;
    uint256 private sLastTimeStamp;
    address private sRecentWinner;
    RaffleState private sRaffleState;

    /**
     * Events
     */
    event EnteredRaffle(address indexed player); //verb based event
    event WinnerPicked(address indexed winner); //verb based event
    event RequestedRaffleWinner(uint256 indexed requestId);
    /**
     * Functions
     */

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    )
        // address vrfCoordinatorV2
        VRFConsumerBaseV2Plus(vrfCoordinator)
    {
        I_ENTRANCE_FEE = entranceFee;
        I_INTERVAL = interval;
        // I_VRF_COORDINATOR = VRFConsumerBaseV2Plus(vrfCoordinator);

        I_KEY_HASH = gasLane;
        I_SUBSCRIPTION_ID = subscriptionId;
        I_CALLBACK_GAS_LIMIT = callbackGasLimit;
        sRaffleState = RaffleState.OPEN;
        sLastTimeStamp = block.timestamp;
    }

    function enterRaffle() external payable {
        // require(msg.value>=I_ENTRANCE_FEE,"Not enough ETH sent");
        if (msg.value < I_ENTRANCE_FEE) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (sRaffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        sPlayers.push(payable(msg.sender));
        // we need any time update the storage ==> emit the event
        emit EnteredRaffle(msg.sender);
    }

    //When should the winner be picked?
    /**
     * @dev This is the function that the Chainlink Keeper nodes will call to see
     * if the lottery is ready to have a winner picked.
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed between raffle runs.
     * 2. The lottery is in an "open" state.
     * 3. The contract has ETH.
     * 4. Implicitly, your subscription is funded with LINK.
     *
     * @param -ignored
     * @return upkeepNeeded -true if it's time to reset the lottery
     * @return -ignored
     */
    function checkUpkeep(bytes memory /*checkData*/ )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */ )
    {
        bool timeHasPassed = ((block.timestamp - sLastTimeStamp) >= I_INTERVAL);
        bool isOpen = sRaffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = sPlayers.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0"); // can we comment this out?
    }

    // 1. Get a random number
    // 2. Use the random number to pick a player
    // 3. Be automatically called
    function performUpkeep(bytes calldata /* performData */ ) external {
        //check if enough time has passed (i_interval)
        (bool upKeepNeeded,) = checkUpkeep("");
        if (!upKeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, sPlayers.length, uint256(sRaffleState));
        }

        sRaffleState = RaffleState.CALCULATING;
        // 1. Request the RNG
        // 2. Get the random number

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: I_KEY_HASH, //gas lane to use, which specifies the maximum gas price to bump to
            subId: I_SUBSCRIPTION_ID, //the subscription id that this contract uses for funding requests
            requestConfirmations: REQUEST_CONFIRMATIONS, //how many confirmations the oracle should wait before responding
            callbackGasLimit: I_CALLBACK_GAS_LIMIT,
            numWords: NUM_WORDS, //the number of uint256 random values to request
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);

        emit RequestedRaffleWinner(requestId);
    }

    //CEI: Checks, Effects, Interactions pattern
    function fulfillRandomWords(uint256, /*requestId*/ uint256[] calldata randomWords) internal override {
        //Checks
        //requires , conditionals

        //s_players = 10
        //rng = 12
        //12 % 10 = 2
        //466888888888888881116564 % 10 = 4

        //Effects(Internal Contract State Changes)
        uint256 indexOfWinner = randomWords[0] % sPlayers.length;
        address payable recentWinner = sPlayers[indexOfWinner];
        sRecentWinner = recentWinner;
        sRaffleState = RaffleState.OPEN;
        sPlayers = new address payable[](0);
        sLastTimeStamp = block.timestamp;
        emit WinnerPicked(recentWinner);

        //Interactions (External Contract Interactions)
        (bool success,) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    // Getter Function
    function getEntranceFee() external view returns (uint256) {
        return I_ENTRANCE_FEE;
    }

    function getRaffleState() external view returns (RaffleState) {
        return sRaffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address player) {
        return sPlayers[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return sLastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return sRecentWinner;
    }
}
