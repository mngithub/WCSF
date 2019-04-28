pragma solidity ^0.5.7;

import "./SafeMath.sol";
import "./StringUtils.sol";
import "./IterableMap.sol";
import "./ERC20.sol";

contract ERC20Votable is ERC20{
    
    // Use itmap for all functions on the struct
    using IterableMap for IterableMap.IMap;
    using SafeMath for uint256;
    
    // event
    event MintToken(uint256 sessionID, address indexed beneficiary, uint256 amount);
    event MintFinished(uint256 sessionID);
    event BurnToken(uint256 sessionID, address indexed beneficiary, uint256 amount);
    event AddAuthority(uint256 sessionID, address indexed authority);
    event RemoveAuthority(uint256 sessionID, address indexed authority);
    event ChangeRequiredApproval(uint256 sessionID, uint256 from, uint256 to);
    
    event VoteAccept(uint256 sessionID, address indexed authority);
    event VoteReject(uint256 sessionID, address indexed authority);
    
    // constant
    uint256 constant NUMBER_OF_BLOCK_FOR_SESSION_EXPIRE = 5760;

    // Declare an iterable mapping
    IterableMap.IMap authorities;
    
    bool public isMintingFinished;
    
    struct Topic {
        uint8 BURN;
        uint8 MINT;
        uint8 MINT_FINISHED;
        uint8 ADD_AUTHORITY;
        uint8 REMOVE_AUTHORITY;
        uint8 CHANGE_REQUIRED_APPROVAL;
    }
    
    struct Session {
        uint256 id;
        uint8 topic;
        uint256 blockNo;
        uint256 referNumber;
        address referAddress;
        uint256 countAccept;
        uint256 countReject;
       // number of approval from authories to accept the current session
        uint256 requireAccept;
    }
    
    ERC20Votable.Topic topic;
    ERC20Votable.Session session;
    
    constructor() public {
        
        topic.BURN = 1;
        topic.MINT = 2;
        topic.MINT_FINISHED = 3;
        topic.ADD_AUTHORITY = 4;
        topic.REMOVE_AUTHORITY = 5;
        topic.CHANGE_REQUIRED_APPROVAL = 6;
        
        session.id = 1;
        session.requireAccept = 1;
    
        authorities.insert(msg.sender, session.id);
    }
    
    /**
     * @dev modifier
     */
    modifier onlyAuthority() {
        require(authorities.contains(msg.sender));
        _;
    }
    
    modifier onlySessionAvailable() {
        require(_isSessionAvailable());
        _;
    }
    
     modifier onlyHasSession() {
        require(!_isSessionAvailable());
        _;
    }
    
    function isAuthority(address _address) public view returns (bool){
        return authorities.contains(_address);
    }

    /**
     * @dev get session detail
     */
    function getSessionName() public view returns (string memory){
        
        bool isSession = !_isSessionAvailable();
        
        if(isSession){
            return (_getSessionName());
        }
        
        return "None";
    }
    
    function getSessionExpireAtBlockNo() public view returns (uint256){
        
        bool isSession = !_isSessionAvailable();
        
        if(isSession){
            return (session.blockNo.add(NUMBER_OF_BLOCK_FOR_SESSION_EXPIRE));
        }
        
        return 0;
    }
    
    function getSessionVoteAccept() public view returns (uint256){
      
        bool isSession = !_isSessionAvailable();
        
        if(isSession){
            return session.countAccept;
        }
        
        return 0;
    }
    
    function getSessionVoteReject() public view returns (uint256){
      
        bool isSession = !_isSessionAvailable();
        
        if(isSession){
            return session.countReject;
        }
        
        return 0;
    }
    
    function getSessionRequiredAcceptVote() public view returns (uint256){
      
        return session.requireAccept;
    }
    
    function getTotalAuthorities() public view returns (uint256){
      
        return authorities.size();
    }
    

    
    /**
     * @dev create session
     */
     
    function createSessionMintToken(address _beneficiary, uint256 _amount) public onlyAuthority onlySessionAvailable {
        
        require(!isMintingFinished);
        require(_amount > 0);
        require(_beneficiary != address(0));
       
        _createSession(topic.MINT);
        session.referNumber = _amount;
        session.referAddress = _beneficiary;
    }
    
    function createSessionMintFinished() public onlyAuthority onlySessionAvailable {
        
        require(!isMintingFinished);
        _createSession(topic.MINT_FINISHED);
        session.referNumber = 0;
        session.referAddress = address(0);
    }
    
    function createSessionBurnAuthorityToken(address _authority, uint256 _amount) public onlyAuthority onlySessionAvailable {
        
        require(_amount > 0);
        require(_authority != address(0));
        require(isAuthority(_authority));
       
        _createSession(topic.BURN);
        session.referNumber = _amount;
        session.referAddress = _authority;
    }
    
    function createSessionAddAuthority(address _authority) public onlyAuthority onlySessionAvailable {
        
        require(!authorities.contains(_authority));
        
        _createSession(topic.ADD_AUTHORITY);
        session.referNumber = 0;
        session.referAddress = _authority;
    }
    
    function createSessionRemoveAuthority(address _authority) public onlyAuthority onlySessionAvailable {
        
        require(authorities.contains(_authority));
        
        // at least 1 authority remain
        require(authorities.size() > 1);
      
        _createSession(topic.REMOVE_AUTHORITY);
        session.referNumber = 0;
        session.referAddress = _authority;
    }
    
    function createSessionChangeRequiredApproval(uint256 _to) public onlyAuthority onlySessionAvailable {
        
        require(_to != session.requireAccept);
        require(_to <= authorities.size());

        _createSession(topic.CHANGE_REQUIRED_APPROVAL);
        session.referNumber = _to;
        session.referAddress = address(0);
    }
    
    /**
     * @dev vote
     */
    function voteAccept() public onlyAuthority onlyHasSession {
        
        // already vote
        require(authorities.get(msg.sender) != session.id);
        
        authorities.insert(msg.sender, session.id);
        session.countAccept = session.countAccept.add(1);
        
        emit VoteAccept(session.id, session.referAddress);
        
        // execute
        if(session.countAccept >= session.requireAccept){
            
            if(session.topic == topic.BURN){
                
                _burnToken();
                
            }else if(session.topic == topic.MINT){
                
                _mintToken();
                
            }else if(session.topic == topic.MINT_FINISHED){
                
                _finishMinting();
                
            }else if(session.topic == topic.ADD_AUTHORITY){
                
                _addAuthority();    
            
            }else if(session.topic == topic.REMOVE_AUTHORITY){
                
                _removeAuthority();  
                
            }else if(session.topic == topic.CHANGE_REQUIRED_APPROVAL){
                
                _changeRequiredApproval();  
                
            }
        }
    }
    
    function voteReject() public onlyAuthority onlyHasSession {
        
        // already vote
        require(authorities.get(msg.sender) != session.id);
        
        authorities.insert(msg.sender, session.id);
        session.countReject = session.countReject.add(1);
        
        emit VoteReject(session.id, session.referAddress);
    }
    
    /**
     * @dev private
     */
    function _createSession(uint8 _topic) internal {
        
        session.topic = _topic;
        session.countAccept = 0;
        session.countReject = 0;
        session.id = session.id.add(1);
        session.blockNo = block.number;
    }
    
    function _getSessionName() internal view returns (string memory){
        
        string memory topicName = "";
        
        if(session.topic == topic.BURN){
          
           topicName = StringUtils.append3("Burn ", StringUtils.uint2str(session.referNumber) , " token(s)");
           
        }else if(session.topic == topic.MINT){
          
           topicName = StringUtils.append4("Mint ", StringUtils.uint2str(session.referNumber) , " token(s) to address 0x", StringUtils.toAsciiString(session.referAddress));
         
        }else if(session.topic == topic.MINT_FINISHED){
          
           topicName = "Finish minting";
         
        }else if(session.topic == topic.ADD_AUTHORITY){
          
           topicName = StringUtils.append3("Add 0x", StringUtils.toAsciiString(session.referAddress), " to authorities");
           
        }else if(session.topic == topic.REMOVE_AUTHORITY){
            
            topicName = StringUtils.append3("Remove 0x", StringUtils.toAsciiString(session.referAddress), " from authorities");
            
        }else if(session.topic == topic.CHANGE_REQUIRED_APPROVAL){
            
            topicName = StringUtils.append4("Change approval from ", StringUtils.uint2str(session.requireAccept), " to ", StringUtils.uint2str(session.referNumber));
            
        }
        
        return topicName;
    }
    
    function _isSessionAvailable() internal view returns (bool){
        
        // vote result accept
        if(session.countAccept >= session.requireAccept) return true;
        
         // vote result reject
        if(session.countReject > authorities.size().sub(session.requireAccept)) return true;
        
        // vote expire (1 day)
        if(block.number.sub(session.blockNo) > NUMBER_OF_BLOCK_FOR_SESSION_EXPIRE) return true;
        
        return false;
    }   
    
    function _addAuthority() internal {
        
        authorities.insert(session.referAddress, session.id);
        emit AddAuthority(session.id, session.referAddress);
    }
    
    function _removeAuthority() internal {
        
        authorities.remove(session.referAddress);
        if(authorities.size() < session.requireAccept){
            emit ChangeRequiredApproval(session.id, session.requireAccept, authorities.size());
            session.requireAccept = authorities.size();
        }
        emit RemoveAuthority(session.id, session.referAddress);
    }
    
    function _changeRequiredApproval() internal {
        
        emit ChangeRequiredApproval(session.id, session.requireAccept, session.referNumber);
        session.requireAccept = session.referNumber;
        session.countAccept = session.requireAccept;
    }
    
    function _mintToken() internal {
        
        require(!isMintingFinished);
        _mint(session.referAddress, session.referNumber);
        emit MintToken(session.id, session.referAddress, session.referNumber);
    }
    
    function _finishMinting() internal {
        
        require(!isMintingFinished);
        isMintingFinished = true;
        emit MintFinished(session.id);
    }
    
    function _burnToken() internal {
        
        _burn(session.referAddress, session.referNumber);
        emit BurnToken(session.id, session.referAddress, session.referNumber);
    }
}

contract WorldClassSmartFarmToken is ERC20Detailed, ERC20Votable {
    constructor (string memory name, string memory symbol, uint8 decimals)
        public
        ERC20Detailed(name, symbol, decimals)
    {
        
    }
}
