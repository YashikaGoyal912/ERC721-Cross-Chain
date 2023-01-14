// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

// We first import ERC721 from Openzeppelin contracts and
// Router's CrossTalk Apllication interface along with Crosstalk Utils
import "evm-gateway-contract/contracts/ICrossTalkApplication.sol";
import "evm-gateway-contract/contracts/Utils.sol";
import "@routerprotocol/router-crosstalk-utils/contracts/CrossTalkUtils.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// We inherit the contracts that we imported to access the inherited contract's methods.
contract XERC721 is ERC721, ICrossTalkApplication {
  address public admin;
  address public gatewayContract;
  uint64 public destGasLimit;
  // chain type + chain id => address of our contract in bytes
  mapping(uint64 => mapping(string => bytes)) public ourContractOnChains;

  // Here we need to initiate our contract with the name and symbol of NFT,
  // gateway address for the chain you are going to deploy this contract on
  // and gas limit for the destination chain you want to interact with.
  constructor(
    string memory _name,
    string memory _symbol,
    address payable gatewayAddress,
    uint64 _destGasLimit
  ) ERC721(_name, _symbol) {
    gatewayContract = gatewayAddress;
    destGasLimit = _destGasLimit;
    admin = msg.sender;
  }

  // This is a function that user shall hit to set the address of this contract's counterparts on other chains
  function setContractOnChain(
    uint64 chainType,
    string memory chainId,
    address contractAddress
  ) external {
    require(msg.sender == admin, "only admin");
    ourContractOnChains[chainType][chainId] = toBytes(contractAddress);
  }

  // This function is responsible for burning the nft on source chain and
  // for generating a cross-chain communication request using Router's Crosstalk
  function transferCrossChain(
    uint64 chainType,
    string memory chainId,
    uint64 expiryDurationInSeconds,
    uint64 destGasPrice,
    bytes memory recipient,
    uint256 id
  ) public payable {
    // burning the NFT from the address of the user calling this function
    _burn(id);

    // encoding the data that we need to use on destination chain to mint an NFT there.
    bytes memory payload = abi.encode(recipient, id);

    // timestamp when the call expires. If this time passes by, the call will fail on the destination chain.
    // If you don't want to add an expiry timestamp, set it to zero.
    uint64 expiryTimestamp = uint64(block.timestamp) + expiryDurationInSeconds;

    // Destination chain params is a struct that consists of gas limit and gas price for destination chain,
    // chain type of the destination chain and chain id of destination chain.
    Utils.DestinationChainParams memory destChainParams = Utils
      .DestinationChainParams(destGasLimit, destGasPrice, chainType, chainId);

    // This is the function to send a single request without acknowledgement to the destination chain.
    // You will be able to send a single request to a single contract on the destination chain and
    // you don't need the acknowledgement back on the source chain.
    CrossTalkUtils.singleRequestWithoutAcknowledgement(
      gatewayContract,
      expiryTimestamp,
      destChainParams,
      ourContractOnChains[chainType][chainId], // destination contract address
      payload
    );
  }

  // This function is responsible to handle requests from source chain on the destination chain
  function handleRequestFromSource(
    bytes memory srcContractAddress,
    bytes memory payload,
    string memory srcChainId,
    uint64 srcChainType
  ) external override returns (bytes memory) {
    // Checks if the contract that triggered this function is address of our gateway contract
    require(msg.sender == gatewayContract);
    require(
      keccak256(srcContractAddress) ==
        keccak256(ourContractOnChains[srcChainType][srcChainId])
    );
    // decoding the data that we encoded to be used for minting the nft on destination chain.
    (bytes memory recipient, uint256 id) = abi.decode(
      payload,
      (bytes, uint256)
    );
    // mints the nft to recipient on destination chain
    _mint(
      // converting the address of recipient from bytes to address
      CrossTalkUtils.toAddress(recipient),
      id
    );

    return abi.encode(srcChainId, srcChainType);
  }

  // This function has to be overridden mandatorily and is used when we
  // get/want an acknowledgement on the source chain.
  function handleCrossTalkAck(
    uint64, //eventIdentifier,
    bool[] memory, //execFlags,
    bytes[] memory //execData
  ) external view override {}

  // This is a function to convert type address into type bytes.
  function toBytes(address a) public pure returns (bytes memory b) {
    assembly {
      let m := mload(0x40)
      a := and(a, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
      mstore(add(m, 20), xor(0x140000000000000000000000000000000000000000, a))
      mstore(0x40, add(m, 52))
      b := m
    }
  }
}
