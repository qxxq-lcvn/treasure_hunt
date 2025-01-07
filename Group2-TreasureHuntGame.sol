// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title TreasureHuntGame
 * @dev A game where players collect treasures represented as NFTs with DID integration and role management.
 * 
 * Team 2 Members:
 * - Hang RithRatana
 * - Leang Menghang
 * - Lim Bunnanvannuth
 * - Lim Chanvina
 * - Sophat Sophanna
 */

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

// Inherit the contract from the 'ERC721URIStorage' contract
contract TreasureHuntGame is ERC721URIStorage {
    // Counter for NFT token IDs
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    // Variables
    uint256 public gridSize;
    uint256 public maxTreasures;

    struct DID {
        string identifier;
        address owner;
        uint256 createdAt;
    }

    struct MetaData {
        string name;
        string email;
        string profilePicture;
    }

    struct Credential {
        address issuer;
        string role;
        uint256 issueAt;
        int salary;
        bytes32 hashes;
        bytes32 salaryhashes;
    }

    struct Player {
        address addr;
        uint256 score;
        uint256 moves;
        uint256 position;
    }

    struct Treasure {
        uint256 id;
        uint256 value;
        bool claimed;
        uint256 position;
    }

    // State variables
    mapping(address => DID) private dids;
    mapping(address => string) private roles;
    mapping(address => string[]) private credentialHistory;
    mapping(address => MetaData) private metadatas;
    mapping(address => Credential[]) private credentials;
    mapping(uint256 => Treasure) public treasures;
    mapping(address => Player) public players;
    mapping(address => bool) public isPlayer;

    // Modifiers - check Conditions
    modifier onlySuperAdmin() {
        require(
            keccak256(abi.encodePacked(roles[msg.sender])) == keccak256(abi.encodePacked("super admin")),
            "Only super admin can perform this action"
        );
        _;
    }

    modifier noRole(string memory _role) {
        require(bytes(_role).length > 0, "Role cannot be empty");
        _;
    }

    modifier noDID(address _user) {
        require(dids[_user].owner != address(0), "No DID found for this user");
        _;
    }

    modifier noCredential(address _user) {
        require(credentials[_user].length > 0, "User does not have a credential");
        _;
    }

    modifier noIssuerDID(address _issuer) {
        require(dids[_issuer].owner != address(0), "No DID found for this issuer");
        _;
    }

    modifier noVerifierDID() {
        require(dids[msg.sender].owner != address(0), "No DID found for this verifier");
        _;
    }

    modifier onlyPlayer() {
        require(isPlayer[msg.sender], "Not a registered player");
        _;
    }

    // Events - Store in Blockchain
    event DIDCreated(address indexed owner, string identifier);
    event SetMetaData(address indexed owner, string name, string email, string profilePicture);
    event CredentialAssigned(address indexed user, string role, int salary);
    event CredentialIssued(address indexed issuer, address indexed receiver, string role, bytes32 hash);
    event RoleVerified(address indexed user, string role, bool isValid);
    event SalaryVerified(address indexed user, bool isValid);
    event TreasurePlaced(uint256 indexed treasureId, uint256 value);
    event PlayerRegistered(address indexed player, uint256 position);
    event PlayerMoved(address indexed player, uint256 remainingMoves);
    event TreasureClaimed(address indexed player, uint256 indexed treasureId, uint256 value);

    // Set the variables needed to be initialized when the game is deployed
    constructor(string memory name, string memory symbol, uint256 initialValue, string memory tokenURI, uint256 _gridSize, uint256 _maxTreasures) 
        ERC721(name, symbol) 
    {
        require(initialValue > 0, "Treasure value must be greater than zero");
        require(_maxTreasures <= _gridSize, "Max treasures cannot exceed grid size");

        roles[msg.sender] = "super admin";
        credentialHistory[msg.sender].push("super admin");

        gridSize = _gridSize;
        maxTreasures = _maxTreasures;
        uint256[] memory positions = new uint256[](gridSize);
   
        for (uint256 i = 0; i < gridSize; i++) {
            positions[i] = i;
        }

        for (uint256 i = 0; i < gridSize; i++) {
            uint256 j = i + uint256(keccak256(abi.encodePacked(block.prevrandao))) % (gridSize - i);
            (positions[i], positions[j]) = (positions[j], positions[i]);
        }

        for (uint256 i = 0; i < maxTreasures; i++) {
            _tokenIds.increment();
            uint256 newTreasureId = _tokenIds.current();
            uint256 treasurePosition = positions[i];
            
            treasures[newTreasureId] = Treasure(newTreasureId, initialValue + i, false, treasurePosition);
            _mint(address(this), newTreasureId);
            _setTokenURI(newTreasureId, tokenURI);

            emit TreasurePlaced(newTreasureId, initialValue + i);
        }
    }

    // Create DID for sender
    function createDID(string memory _identifier) public {
        require(bytes(_identifier).length > 0, "Identifier cannot be empty");
        require(dids[msg.sender].owner == address(0), "DID already exists");

        dids[msg.sender] = DID(_identifier, msg.sender, block.timestamp);
        
        emit DIDCreated(msg.sender, _identifier);
    }

    // Get DID
    function getDID() public noDID(msg.sender) view returns (string memory) {
        return dids[msg.sender].identifier;
    }

    // Input metadata of the sender
    function setMetadata(string memory name, string memory email, string memory profilePicture) public noDID(msg.sender) {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(email).length > 0, "Email cannot be empty");
        require(bytes(profilePicture).length > 0, "Profile picture cannot be empty");

        metadatas[msg.sender] = MetaData(name, email, profilePicture);

        emit SetMetaData(msg.sender, name, email, profilePicture);
    }

    // Get metadata
    function getMetadata() public view returns (MetaData memory) {
        require(dids[msg.sender].owner != address(0), "No metadata found for this address");

        return metadatas[msg.sender];
    }

    // Set credential information for users by Super admin
    function assignCredential(address _user, string memory _role, int _salary) public onlySuperAdmin noRole(_role) {
        roles[_user] = _role;
        credentialHistory[_user].push(_role);

        emit CredentialAssigned(_user, _role, _salary);
    }

    // Issue the assigned credential by Super admin
    function issueCredential(address _user, string memory _role, int _salary) public onlySuperAdmin noRole(_role) {
        address _issuer = msg.sender;
        bytes32 roleHash = keccak256(abi.encodePacked(msg.sender, _user, _role, block.timestamp));
        bytes32 salaryHash = keccak256(abi.encodePacked(msg.sender, _user, _salary, block.timestamp));

        credentials[_user].push(Credential(_issuer, _role, block.timestamp, _salary, roleHash, salaryHash));
        credentialHistory[_user].push(_role);

        emit CredentialIssued(_issuer, _user, _role, roleHash);
    }

    // Verify the role of a user by the Issuer
    function verifyRole(address _user, string memory _role, address _issuer) public noDID(_user) noRole(_role) noCredential(_user) noIssuerDID(_issuer) noVerifierDID returns (bool isValid) {
        string memory userRole = roles[_user];
        Credential[] memory userCredential = credentials[_user];
        
        for(uint256 i = 0; i < userCredential.length; i++) {
            if(userCredential[i].issuer == _issuer && keccak256(bytes(userRole)) == keccak256(bytes(_role))) {
                emit RoleVerified(_user, _role, true);
                return true;
            } else {
                emit RoleVerified(_user, _role, false);
            }
        }
        return false;
    }

    // Verify the salary of a user by the Issuer
    function verifySalary(address _user, int _salary, address _issuer) public noDID(_user) noCredential(_user) noIssuerDID(_issuer) noVerifierDID returns (bool isValid) {
        require(_salary > 0, "Salary cannot be empty");

        Credential[] memory userCredential = credentials[_user];
        
        for(uint256 i = 0; i < userCredential.length; i++) {
            if(userCredential[i].issuer == _issuer && userCredential[i].salary > 300) {
                emit SalaryVerified(_user, true);
                return true;
            } else {
                emit SalaryVerified(_user, false);
            }
        }
        return false;
    }

    // Get the credential information
    function getCredential() public view returns (string[] memory) {
        return credentialHistory[msg.sender];
    }

    // Register the user as a player
    function registerPlayer() public noDID(msg.sender) {
        require(players[msg.sender].addr == address(0), "Player already registered");

        players[msg.sender] = Player(msg.sender, 0, 10, 0);

        emit PlayerRegistered(msg.sender, players[msg.sender].position);
    }

    // Get the player information
    function getPlayer(address player) public onlyPlayer view returns (Player memory) {
        return players[player];
    }

    // Move player to a certain position
    function movePlayer(uint256 newPosition) public onlyPlayer {
        require(players[msg.sender].moves > 0, "No moves left");

        players[msg.sender].position = newPosition;
        players[msg.sender].moves--;

        emit PlayerMoved(msg.sender, players[msg.sender].moves);
    }

    // Claim the treasure when player is on the same position
    function claimTreasure(uint256 treasureId) public onlyPlayer {
        require(players[msg.sender].moves > 0, "No moves left to claim a treasure");
        require(treasures[treasureId].id == treasureId, "Treasure does not exist");
        require(!treasures[treasureId].claimed, "Treasure already claimed");
        require(players[msg.sender].position == treasures[treasureId].position, "Player not at treasure location");

        treasures[treasureId].claimed = true;
        _transfer(address(this), msg.sender, treasureId);
        players[msg.sender].score += treasures[treasureId].value;
        players[msg.sender].moves--;

        emit TreasureClaimed(msg.sender, treasureId, treasures[treasureId].value);
    }

    // Get the treasure position
    function getTreasurePosition(uint256 treasureId) public view returns (uint256) {
        require(treasures[treasureId].id == treasureId, "Treasure does not exist");

        return treasures[treasureId].position; // Return the position of the specified treasure
    }
}
