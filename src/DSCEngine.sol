//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;

/** 
@title DSCEngine
@author HemaDeviU
The system is designed to be as minimal as possible and have the tokens maintain 1 token == 1$ peg
The stablecoin has properties Exogenous Collateral,dollar pegged, algorithmically stable
It's similar to DAI is DAI had no governance, no fees and only backed by WETH and WBTC
The DSC system should always be overcollateralized, always all collateral <= value of all the DSC
*/
import {OracleLib} from "./libraries/OracleLib.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import {DecentralizedStableCoin} from "./decentralizedStableCoin.sol";


contract DSCEngine is ReentrancyGuard {
    //errrors

    error DSCEngine__NeedMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    //Types
    using OracleLib for AggregatorV3Interface;

    //State Variables
    DecentralizedStableCoin private immutable i_dsc;
    address[] private s_collateralTokens;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; 
    uint256 private constant PRECISION =1e18;
    uint256 private constant LIQUIDATION_PRECISION =100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant FEED_PRECISION = 1e8;

    //mappings
    mapping(address collateralToken => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address collateralToken => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    //events
    event CollateralDeposited(address indexed user,address indexed token,uint256 indexed amount );
    event CollateralRedeemed(address indexed redeemFrom,address indexed redeemTo, address indexed token, uint256  amount);

    //modifiers
    modifier moreThanZero(uint256 amount) 
    {
        if (amount == 0) 
        {
            revert DSCEngine__NeedMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if ((s_priceFeeds[token]) == address(0)) 
        {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    //functions
    constructor( address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) 
    {
        if (tokenAddresses.length != priceFeedAddresses.length) 
        {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) 
        {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //external functions
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external 
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress)
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant isAllowedToken(tokenCollateralAddress)
    {
       _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
       _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 amount) external moreThanZero(amount) 
    {
       _burnDsc(amount,msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);

    }

    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if(startingUserHealthFactor >= MIN_HEALTH_FACTOR )
        {
            revert DSCEngine__HealthFactorOk();

        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS)/LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if(endingUserHealthFactor <= startingUserHealthFactor)
        {
            revert DSCEngine__HealthFactorNotImproved();
        }
    }


    //Public Functions
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant 
    {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender,amountDscToMint);
        if(!minted)
        {
            revert DSCEngine__MintFailed();
        }
    }

    function depositCollateral(address tokenCollateralAddress,uint256 amountCollateral)public moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender,tokenCollateralAddress,amountCollateral);
        
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender,address(this),amountCollateral );
        if (!success) 
        {
            revert DSCEngine__TransferFailed();
        }

    }
    //Private functions
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf,address dscFrom) private
    {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if(!success)
        {
            revert DSCEngine__TransferFailed();

        }
        i_dsc.burn(amountDscToBurn);
    } 
    function _redeemCollateral (address tokenCollateralAddress,uint256 amountCollateral,address from,address to) private
    {
         s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if(!success)
        {
        revert DSCEngine__TransferFailed();
        }

    }

    //Private and Internal (View & Pure) Functions

    function _getAccountInformation(address user)private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) 
    {
        
        ( uint256 totalDscMinted, uint256 collateralValueInUsd ) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function _getUsdValue(address token,uint256 amount) private view returns (uint256) 
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / 1e18;
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) internal pure returns(uint256)
    {
    if(totalDscMinted == 0) return type(uint256).max;
    uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD)/LIQUIDATION_PRECISION;
    return(collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }


    function _revertIfHealthFactorIsBroken(address user) internal view 
    {
        uint256 userHealthFactor = _healthFactor(user);
        if(userHealthFactor < MIN_HEALTH_FACTOR) 
        {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }

    }


    //(External and Public) View & Pure functions

    function getTokenAmountFromUsd(address token,uint256 usdAmountInWei) public view returns (uint256 totalCollateralValueInUsd)    
    {
    AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
    (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
    return (usdAmountInWei * PRECISION)/(uint256(price)* ADDITIONAL_FEED_PRECISION);
    }


    function getAccountCollateralValue( address user) public view returns (uint256 totalCollateralValueInUsd) 
    {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) 
        {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += _getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }
    
    function getAccountInformation(address user) external view returns(uint256 totalDscMinted, uint256 collateralValueInUsd){
        return _getAccountInformation(user);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd) external pure returns(uint256)
    {

        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }
    function getUsdValue(address token, uint256 amount) external view returns(uint256)
    {
        return _getUsdValue(token, amount);
    }
    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256)
    {
        return s_collateralDeposited[user][token];
    }
    function getPrecision() external pure returns (uint256){
        return PRECISION;
    }
    function getAdditionalFeedPrecision() external pure returns(uint256){
        return ADDITIONAL_FEED_PRECISION;
    }
    function getLiquidationThreshold() external pure returns (uint256){
        return LIQUIDATION_THRESHOLD;
    }
    function getLiquidationBonus() external pure returns(uint256){
        return LIQUIDATION_BONUS;
    }
    function getLiquidationPrecision() external pure returns(uint256){
        return LIQUIDATION_PRECISION;
    }
    function getDsc() external view returns(address){
        return address(i_dsc);
    }
    function getCollateralTokenPriceFeed(address token) external view returns (address){
        return s_priceFeeds[token];
    }
    function getMinHealthFactor() external pure returns (uint256){
        return MIN_HEALTH_FACTOR;
    }
    function getHealthFactor(address user) external view returns (uint256){
        return _healthFactor(user);
    }
    function getCollateralTokens() external view returns (address[] memory){
        return s_collateralTokens;
    }
}

