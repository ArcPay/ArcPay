// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IncrementalTreeData, IncrementalBinaryTree} from "./IncrementalBinaryTree.sol";
import {Ownable2Step} from "../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import {ECDSA} from "../lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {PoseidonT3} from "../lib/poseidon-solidity/contracts/PoseidonT3.sol";
import {PoseidonT5} from "../lib/poseidon-solidity/contracts/PoseidonT5.sol";
import {PoseidonT6} from "../lib/poseidon-solidity/contracts/PoseidonT6.sol";

struct Force {
    uint hash;
    uint time;
}

struct OwnershipRequest {
    uint coin;
    uint blockNumber;
    uint time;
    bytes32 responseHash;
}

contract ArcPay is Ownable2Step {
    event Mint(address receiver, uint lowCoin, uint highCoin);

    string internal constant ERROR_MINT_EMPTY = "E1";
    string internal constant ERROR_FORCE_NO_COIN = "E2";
    string internal constant ERROR_SLASH_NO_FORCE = "E3";
    string internal constant ERROR_SLASH_NOT_OLD = "E4";
    string internal constant ERROR_DOUBLE_RESPONSE = "E5";
    string internal constant ERROR_NONMATCHING_RESPONSE = "E6";
    string internal constant ERROR_MINT_SLASH_NO_FORCE = "E7";
    string internal constant ERROR_MINT_SLASH_NOT_OLD = "E8";
    string internal constant ERROR_SLASH_AMOUNT_NOT_SENT= "E9";

    using IncrementalBinaryTree for IncrementalTreeData;

    uint internal constant ZERO = 0;
    uint internal constant DEPTH = 20;
    uint internal constant FORCE_WAIT = 1 days;
    uint internal constant REQUEST_WAIT = 1 days;

    uint public mintHashChain;
    uint provedMintTimeStamp = 0;
    mapping(uint mintHash => uint timestamp) mints;

    uint[] public stateHistory;
    uint public stateRoot;

    OwnershipRequest[] public ownershipRequests;

    Force[] public forcedInclusions;

    uint maxCoin = 0;

    constructor(address _owner) {
        _transferOwnership(_owner);
    }

    function _slash() internal {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}(""); // EXTERNAL CALL
        require(success, ERROR_SLASH_AMOUNT_NOT_SENT);
    }

    function mint(address receiver) external payable returns (uint) {
        require(msg.value > 0, ERROR_MINT_EMPTY);
        mintHashChain = PoseidonT5.hash([uint(uint160(receiver)), maxCoin, maxCoin+msg.value-1, mintHashChain]);
        mints[mintHashChain] = block.timestamp;
        emit Mint(receiver, maxCoin, maxCoin+msg.value);
        maxCoin += msg.value;
        return mintHashChain;
    }

    function forceInclude(address receiver, uint[2] calldata leafCoins, uint highestCoinToSend, bytes memory signature) external {
        require(highestCoinToSend < maxCoin, ERROR_FORCE_NO_COIN);
        uint hash = PoseidonT5.hash([leafCoins[0], leafCoins[1], highestCoinToSend, uint(uint160(receiver))]);
        require(msg.sender == ECDSA.recover(bytes32(hash), signature));

        forcedInclusions.push(Force({
            hash: hash,
            time: block.timestamp
        }));
    }

    function slashForLateInclusion(uint i) external {
        require(forcedInclusions[i].time != 0, ERROR_SLASH_NO_FORCE);
        require (block.timestamp - forcedInclusions[i].time > FORCE_WAIT, ERROR_SLASH_NOT_OLD);

        _slash();
    }

    function slashForLateMintInclusion(address receiver, uint lowCoin, uint highCoin, uint _mintHashChain) external {
        uint hash = PoseidonT5.hash([uint(uint160(receiver)), lowCoin, highCoin, _mintHashChain]);
        require(mints[hash] > 0, ERROR_MINT_SLASH_NO_FORCE);
        require(block.timestamp - mints[hash] > FORCE_WAIT, ERROR_MINT_SLASH_NOT_OLD);

        _slash();
    }

    function updateState(uint _stateRoot, uint mintTime) external onlyOwner {
        stateRoot = _stateRoot;
        stateHistory.push(_stateRoot);
        provedMintTimeStamp = mintTime;
    }

    function requestOwnerShipProof(uint coin, uint blockNumber) external {
        ownershipRequests.push(OwnershipRequest({
            coin: coin,
            blockNumber: blockNumber,
            time: block.timestamp,
            responseHash: 0
        }));
    }

    function slashForLateResponse(uint i) external {
        require(ownershipRequests[i].time != 0, ERROR_SLASH_NO_FORCE);
        require (block.timestamp - ownershipRequests[i].time > REQUEST_WAIT, ERROR_SLASH_NOT_OLD);

        _slash();
    }

    function respondToOwnershipRequest(uint i, bool[DEPTH] calldata pathIndices, uint[DEPTH] calldata pathElements, uint lowerCoin, uint upperCoin, uint owner) external {
        require(ownershipRequests[i].time != 0, ERROR_DOUBLE_RESPONSE);
        ownershipRequests[i].time = 0;
        ownershipRequests[i].responseHash = keccak256(abi.encodePacked(pathIndices, pathElements, lowerCoin, upperCoin, owner));
    }

    function slashForInvalidOwnershipProof(uint i, bool[DEPTH] calldata pathIndices, uint[DEPTH] calldata pathElements, uint lowerCoin, uint upperCoin, uint owner) external {
        require(keccak256(abi.encodePacked(pathIndices, pathElements, lowerCoin, upperCoin, owner)) == ownershipRequests[i].responseHash, ERROR_NONMATCHING_RESPONSE);
        // TODO: require that the proof is valid for that `blockNumber`th block in stateHistory

        _slash();
    }

    function slashForBrokenPromise() external {
        // TODO: show that the promise was signed by the operator (does transferable ownership make this tricky?)
        // TODO: show that the promise contradicts a response in ownershipRequests

        _slash();
    }

    // any eth sent is part of the slashable stake
    receive() external payable {}
}

