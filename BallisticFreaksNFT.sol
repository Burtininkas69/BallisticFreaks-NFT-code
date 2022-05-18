// SPDX-License-Identifier: MIT

pragma solidity >= 0.7 .0 < 0.9 .0;

/// @title BallisticFreaks contract
/// @author Gustas K (ballisticfreaks@gmail.com)
/// @notice we won't have whitelisted mint in our release version. This is if someone want's to use it and have Whitelist option

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BallisticFreaksNFT is ERC721Enumerable,
Ownable {
    using Strings
    for uint256;

    /// @notice contract is created with 2 founders. So withdrawal is split 50/50
    address public coFounder;

    string public baseURI;
    string public notRevealedUri;
    string public baseExtension = ".json";

    /// @notice edit these before launching contract
    /// @dev only ReferralRewardPercentage & costToCreateReferral is editable
    uint8 public referralRewardPercentage = 20;
    uint16 public nonce = 1;
    /// @notice we will not release full supply until the game is finished
    uint16 constant public maxSupplyBeforeGame = 2000;
    uint16 constant public maxSupply = 10000;
    uint256 public cost = 0.05 ether;
    uint256 public referralCost = 0.045 ether;
    uint256 public costToCreateReferral = 0.015 ether;

    /// @notice this uint prevents owners from withdrawing referral payouts from contract
    uint256 internal referralObligationPool;

    bool public paused = false;
    bool public revealed = false;
    bool public frozenURI = false;
    /// @notice gameIsLaunched will only be true once we launch our game. This prevents you from minting more than locked supply
    bool public gameIsLaunched = false;

    /// @notice used to find unminted ID
    uint16[maxSupply] public mints;

    mapping(address => uint) public mintsReferred;
    mapping(address => uint) public refObligation;
    mapping(string => bool) public codeIsTaken;
    mapping(string => address) internal ownerOfCode;

    constructor(string memory _name,
        string memory _symbol,
        address _coFounder,
        string memory _unrevealedURI) ERC721(_name, _symbol) {
        setUnrevealedURI(_unrevealedURI);
        coFounder = _coFounder;

    /// @notice an array of lets say 10,000 numbers would be too long to hardcode it. So we are using constructor to generate all numbers for us.
    /// @dev generates all possible IDs of NFTs that our findUnminted() function picks from
        for (uint16 i = 0; i < maxSupply; ++i) {
            mints[i] = i;
        }
    }

    modifier notPaused {
        require(!paused);
        _;
    }

    function _baseURI() internal view virtual override returns(string memory) {
        return baseURI;
    }

    /// @notice returns a semi-random number
    /// @dev this function is not very secure. While it provides randomness, it can be abused. But in our case for snipers it's not worth the hussle.
    /// wouldn't use it for anything more that could have a big financial gain (for example in game function)
    /// originally planned to have a chainlink implementation, but with that mint code exceeds 24576 bytes.
    function random(uint _limit) internal returns(uint16) {
        uint randomnumber = (uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, nonce))) % (_limit + 1));
        nonce++;
        return uint16(randomnumber);
    }

    /// @notice calls for random number and picks corresponding NFT
    /// @dev deletes used ID from array and moves the last uint to it's place. Also shortens arrays length, so it would be impossible to pick same number.
    function findUnminted() internal returns(uint) {
        uint supply = totalSupply();
        uint index = random(maxSupply - supply - 1);
        uint chosenNft = mints[index];
        uint swapNft = mints[maxSupply - supply - 1];
        mints[index] = uint16(swapNft);
        return (chosenNft);
    }

    /// @notice Chosen code (string) get's assigned to address. Whenever the code is used in mint, assigned address is paid.
    function createRefferalCode(address _address, string memory _code) public payable {
        require(keccak256(abi.encodePacked(_code)) != keccak256(abi.encodePacked("")), "Referral Code can't be empty");
        require(!codeIsTaken[_code], "Referral Code is already taken");

        if (msg.sender != owner()) {
            require(msg.value >= costToCreateReferral, "Value should be equal or greater than ReferralCost");
        }

        codeIsTaken[_code] = true;
        ownerOfCode[_code] = _address;
    }

    /// @notice mint function with referral code to give user discount and pay referral
    /// @dev function has an extra input - string. It is used for referral code. If the user does not put any code, string looks like this "".
    function mint(address _to, uint256 _mintAmount, string memory _code) public payable notPaused {
        uint256 supply = totalSupply();
        require(_mintAmount > 0);

        if (!gameIsLaunched) {
            require(supply + _mintAmount <= maxSupplyBeforeGame);
        } else {
            require(supply + _mintAmount <= maxSupply);
        }

        require(codeIsTaken[_code] || keccak256(abi.encodePacked(_code)) == keccak256(abi.encodePacked("")), "Referral not valid, find a valid code or leave the string empty ");

        if (msg.sender != owner()) {
            if (codeIsTaken[_code]) {
                require(ownerOfCode[_code] != msg.sender, "You can't referr yoursef");
                require(msg.value >= (referralCost * _mintAmount), "ReferralMint: Not enough ether");
            } else {
                require(msg.value >= cost * _mintAmount, "MintWithoutReferral: Not enough ether");
            }
        }

        for (uint256 i = 0; i < _mintAmount; i++) {
            _safeMint(_to, findUnminted());
        }

        /// @dev makes temp uint of referral payout, adds mint ammount to referral counter, adds payout to code owners array, updates contracts obligation pool
        uint _refPayout = msg.value / 100 * referralRewardPercentage;
        mintsReferred[ownerOfCode[_code]] = mintsReferred[ownerOfCode[_code]] + _mintAmount;
        refObligation[ownerOfCode[_code]] = refObligation[ownerOfCode[_code]] + _refPayout;
        referralObligationPool = referralObligationPool + _refPayout;
    }

    /// @notice referral address will be able to call this function and receive obligated eth amount from all referred mints
    function withdrawReferralPayout() public {

        ///@dev makes temp uint of referral payout, decreases contracts obligation pool, nulls senders referral reward array and sends payout to the address
        uint _refPayout = refObligation[msg.sender];
        referralObligationPool = referralObligationPool - _refPayout;
        refObligation[msg.sender] = 0;
        (bool ro, ) = payable(msg.sender).call {value: _refPayout}("");
        require(ro);
    }


    function walletOfOwner(address _owner) public view returns(uint256[] memory) {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);

        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }

        return tokenIds;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns(string memory) {
        require(_exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (revealed == false) {
            return notRevealedUri;
        }

        string memory currentBaseURI = _baseURI();
        return bytes(currentBaseURI).length > 0 ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension)) : "";
    }

    //only owner

    /// @notice releaseGame states that our game is released and now let's users mint remaining NFTs
    function releaseGame() public onlyOwner {
        gameIsLaunched = true;
    }

    function changeReferralRewardAndCost(uint8 _percentage) public onlyOwner {
        require(_percentage <= 100);
        referralRewardPercentage = _percentage;
    }

    function changeReferralCost(uint _cost) public onlyOwner {
        costToCreateReferral = _cost;
    }

    function freezeURI() public onlyOwner {
        frozenURI = true;
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        require(!frozenURI, "URI is frozen");
        baseURI = _newBaseURI;
    }

    function setUnrevealedURI(string memory _unrevealedURI) public onlyOwner {
        require(!frozenURI, "URI is frozen");
        notRevealedUri = _unrevealedURI;
    }

    function setBaseExtension(string memory _newBaseExtension) public onlyOwner {
        baseExtension = _newBaseExtension;
    }

    function reveal() public onlyOwner {
        revealed = true;
    }

    /// @notice emergency pause. If something goes wrong, we could pause the mint function
    function pause(bool _state) public onlyOwner {
        paused = _state;
    }

    /// @notice only co-founder can call this
    function editCoFounder(address _address) public {
        require(msg.sender == coFounder);
        coFounder = _address;
    } 

    /// @notice balance is split 50/50 to founder & coFounder
    function withdraw() public onlyOwner {
        uint halfBalance = (address(this).balance - referralObligationPool) / 2;
        (bool oc, ) = payable(owner()).call {value: halfBalance}("");

        (bool cc, ) = payable(coFounder).call {value: halfBalance}("");
        require(oc && cc);
    }
}
