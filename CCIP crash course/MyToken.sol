// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract Messenger is CCIPReceiver, OwnerIsCreator, ERC20 {
    
    error NotEnoughBalance(uint256 currentBalance, uint256 calculatedFees); 
    error NothingToWithdraw(); 
    error FailedToWithdrawEth(address owner, address target, uint256 value); 
    error DestinationChainNotAllowlisted(uint64 destinationChainSelector); 
    error SourceChainNotAllowlisted(uint64 sourceChainSelector); 
    error SenderNotAllowlisted(address sender); 


    bytes32 public constant MINT = "MINT";

    
    event MessageSent(
        bytes32 indexed messageId, 
        uint64 indexed destinationChainSelector, 
        address receiver, 
        bytes32 message,
        address _recipient, 
        address feeToken, 
        uint256 fees 
    );

    event MessageReceived(
        bytes32 indexed messageId, 
        uint64 indexed sourceChainSelector,
        address sender,
        bytes32 text, 
        address recipient
    );

    bytes32 private s_lastReceivedMessageId; 
    bytes32 private s_lastReceivedText;

    mapping(uint64 => bool) public allowlistedDestinationChains;

    mapping(uint64 => bool) public allowlistedSourceChains;

    mapping(address => bool) public allowlistedSenders;

    IERC20 private s_linkToken;

    event msgRecieved(uint64 chainSelector, address sender);
    constructor(address _router, address _link) CCIPReceiver(_router) ERC20("WebDevSoultions", "WDS") {
        s_linkToken = IERC20(_link);
    }


    modifier onlyAllowlistedDestinationChain(uint64 _destinationChainSelector) {
        if (!allowlistedDestinationChains[_destinationChainSelector])
            revert DestinationChainNotAllowlisted(_destinationChainSelector);
        _;
    }


    modifier onlyAllowlisted(uint64 _sourceChainSelector, address _sender) {
        emit msgRecieved(_sourceChainSelector, _sender);
        if (!allowlistedSourceChains[_sourceChainSelector])
            revert SourceChainNotAllowlisted(_sourceChainSelector);
        if (!allowlistedSenders[_sender]) revert SenderNotAllowlisted(_sender);
        _;
    }

    function allowlistDestinationChain(
        uint64 _destinationChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedDestinationChains[_destinationChainSelector] = allowed;
    }

    function allowlistSourceChain(
        uint64 _sourceChainSelector,
        bool allowed
    ) external onlyOwner {
        allowlistedSourceChains[_sourceChainSelector] = allowed;
    }

    function allowlistSender(address _sender, bool allowed) external onlyOwner {
        allowlistedSenders[_sender] = allowed;
    }


    function sendMessagePayLINK(
        uint64 _destinationChainSelector,
        address _receiver,
        bytes32 message,
        address _recipient
    )
        external
        onlyOwner
        onlyAllowlistedDestinationChain(_destinationChainSelector)
        returns (bytes32 messageId)
    {
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            _receiver,
            message,
            _recipient,
            address(s_linkToken)
        );

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fees = router.getFee(_destinationChainSelector, evm2AnyMessage);

        if (fees > s_linkToken.balanceOf(address(this)))
            revert NotEnoughBalance(s_linkToken.balanceOf(address(this)), fees);

        s_linkToken.approve(address(router), fees);

        messageId = router.ccipSend(_destinationChainSelector, evm2AnyMessage);

        emit MessageSent(
            messageId,
            _destinationChainSelector,
            _receiver,
            message,
            _recipient,
            address(s_linkToken),
            fees
        );

        return messageId;
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
        internal
        override
        onlyAllowlisted(
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address)))
    {
        address user;
        s_lastReceivedMessageId = any2EvmMessage.messageId; 
        (s_lastReceivedText, user) = abi.decode(any2EvmMessage.data, (bytes32, address)); 

        if(s_lastReceivedText == MINT){
            super._mint(user, 1e18);
        }

        emit MessageReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            abi.decode(any2EvmMessage.sender, (address)), 
            s_lastReceivedText,
            user
        );
    }


    function _buildCCIPMessage(
        address _receiver,
        bytes32 message,
        address _recipient,
        address _feeTokenAddress
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        return
            Client.EVM2AnyMessage({
                receiver: abi.encode(_receiver), 
                data: abi.encode(message, _recipient), 
                tokenAmounts: new Client.EVMTokenAmount[](0), 
                extraArgs: Client._argsToBytes(
                    Client.EVMExtraArgsV1({gasLimit: 200_000_0})
                ),
                feeToken: _feeTokenAddress
            });
    }


    function getLastReceivedMessageDetails()
        external
        view
        returns (bytes32 messageId, bytes32 text)
    {
        return (s_lastReceivedMessageId, s_lastReceivedText);
    }

    receive() external payable {}

    function withdraw(address _beneficiary) public onlyOwner {
        uint256 amount = address(this).balance;

        if (amount == 0) revert NothingToWithdraw();

        (bool sent, ) = _beneficiary.call{value: amount}("");

        if (!sent) revert FailedToWithdrawEth(msg.sender, _beneficiary, amount);
    }

    function withdrawToken(
        address _beneficiary,
        address _token
    ) public onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));

        if (amount == 0) revert NothingToWithdraw();

        IERC20(_token).transfer(_beneficiary, amount);
    }
}



// mumbai: 
// chain selector: 12532609583862916517
// router: 0x1035cabc275068e0f4b745a29cedf38e13af41b1
// link: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB

// sepolia: 
// chain selector: 16015286601757825753
// router: 0x0bf3de8c5d3e8a2b34d2beeb17abfcebaf363a59
// link: 0x779877A7B0D9E8603169DdbD7836e478b4624789