//SPDX-License-Identifier:MIT

pragma solidity 0.8.19;
import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC20Mock.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";

contract DSCEngineTest is StdCheats,Test{
    event CollateralRedeemed(address indexed redeemFrom,address indexed redeemTo,address token, uint256 amount);
    
    DecentralizedStableCoin public dsc;
    DSCEngine public dsce;
    HelperConfig public helperconfig;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;
    address public user = address(1);
    uint256 public  amountCollateral = 10 ether;
    uint256 public  amountToMint = 100 ether;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;


    function setUp() public {
        DeployDSC deployer = new DeployDSC();
        (dsc, dsce, helperconfig) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed,weth,wbtc,deployerKey) = helperconfig.activeNetworkConfig();
        if(block.chainid ==31337){
            vm.deal(user,STARTING_USER_BALANCE);
        }
        
        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);

    }
    //Constructor test
    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public
    {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses,address(dsc));

    }

    //PriceTest
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd  = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth,ethAmount);
        assertEq(expectedUsd, actualUsd);


    }
    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        dsce.depositCollateral(weth,0);
        vm.stopPrank();

    }
    function testGetTokenAmountFromUsd() public{
        uint256 usdAmount =100 ether;
        uint256 expectedWeth =0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth,actualWeth);

    }
    function testrevertWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN","RAN",user, amountCollateral);
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken),amountCollateral);
        vm.stopPrank();

    }
    modifier depositedCollateral(){
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }
    function testCanDepositCollateralAndAccountInfo() public depositedCollateral{
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(user);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth,collateralValueInUsd);
        assertEq(totalDscMinted,expectedTotalDscMinted);
        assertEq(amountCollateral, expectedDepositAmount);

    } 
    //depositcollateral and mint dsc tests
    function testRevertsIfMintedDscBreaksHealthFactor() public {
        (,int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (amountCollateral *(uint256(price)* dsce.getAdditionalFeedPrecision()))/dsce.getPrecision();
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce),amountCollateral);
        uint256 expectedHealthFactor=dsce.calculateHealthFactor(amountToMint,dsce.getUsdValue(weth,amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector,expectedHealthFactor));
        dsce.depositCollateralAndMintDsc(weth,amountCollateral,amountToMint);
        vm.stopPrank();
    }
    modifier depositedCollateralAndMintedDsc(){
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce),amountCollateral);
        dsce.depositCollateralAndMintDsc(weth,amountCollateral,amountToMint);
        vm.stopPrank();
        _;
    }
    function testCanMintWithDespoitedCollateral() public depositedCollateralAndMintedDsc(){
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance,amountToMint);
    }
    //mintDscTests
    function testRevertsIfMintFails() public {
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses = [weth];
        priceFeedAddresses= [ethUsdPriceFeed];
        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses,priceFeedAddresses,address(mockDsc));
        mockDsc.transferOwnership(address(mockDsce));
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(mockDsce),amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDsce.depositCollateralAndMintDsc(weth,amountCollateral,amountToMint);
        vm.stopPrank();
    }
    
    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce),amountCollateral);
        dsce.depositCollateralAndMintDsc(weth, amountCollateral,amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }
    function testRevertsIfMintAmountBreaksHealthFactor() public depositedCollateral{
        (,int256 price, , ,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        amountToMint = (amountCollateral * (uint256(price)* dsce.getAdditionalFeedPrecision()))/dsce.getPrecision();
        vm.startPrank(user);
        uint256 expectedHealthFactor = dsce.calculateHealthFactor(amountToMint,dsce.getUsdValue(weth,amountCollateral));
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector,expectedHealthFactor));
        dsce.mintDsc(amountToMint);
        vm.stopPrank();

    }
    function testCanMintDsc() public depositedCollateral {
        vm.prank(user);
        dsce.mintDsc(amountToMint);

    }
    //burndsc tests
    function testRevertsIfBurnAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce),amountCollateral);
        dsce.depositCollateralAndMintDsc(weth,amountCollateral,amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }
    function testCantBurnMoreThanUserHas() public {
        vm.prank(user);
        vm.expectRevert();
        dsce.burnDsc(1);
    }
    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        dsc.approve(address(dsce),amountToMint);
        dsce.burnDsc(amountToMint);
        vm.stopPrank();
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance,0);
    }
    //redeemcollateraltests
    function testRevertsIfTransferFails() public {
        address owner = msg.sender;
        vm.prank(owner);
        MockFailedTransfer mockDsc = new MockFailedTransfer();
        tokenAddresses = [address(mockDsc)];
        priceFeedAddresses =  [ethUsdPriceFeed];
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(tokenAddresses,priceFeedAddresses,address(mockDsc));
        mockDsc.mint(user,amountCollateral);
        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDsce));
        vm.startPrank(user);
        ERC20Mock(address(mockDsc)).approve(address(mockDsce),amountCollateral);
        mockDsce.depositCollateral(address(mockDsc),amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__TransferFailed.selector);
        mockDsce.redeemCollateral(address(mockDsc),amountCollateral);
        vm.stopPrank();
    }
    function testRevertsIfRedeemAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dsce),amountCollateral);
        dsce.depositCollateralAndMintDsc(weth,amountCollateral,amountToMint);
        vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
        dsce.redeemCollateral(weth,0);
        vm.stopPrank();
    }
    function testCanRedeemCollateral() public depositedCollateral{
        vm.startPrank(user);
        dsce.redeemCollateral(weth,amountCollateral);
        uint256 userBalance = ERC20Mock(weth).balanceOf(user);
        assertEq(userBalance,amountCollateral);
        vm.stopPrank();
    }
    function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateral {
    vm.expectEmit(true,true,true,true,address(dsce));
    emit CollateralRedeemed(user,user,weth,amountCollateral);
    vm.startPrank(user);
    dsce.redeemCollateral(weth,amountCollateral);
    vm.stopPrank();
 }
 //redeemCollateralForDSc tests
 function testMustRedeemMoreThanZero() public depositedCollateralAndMintedDsc {
    vm.startPrank(user);
    dsc.approve(address(dsce),amountToMint);
    vm.expectRevert(DSCEngine.DSCEngine__NeedMoreThanZero.selector);
    dsce.redeemCollateralForDsc(weth,0,amountToMint);
    vm.stopPrank();
 }
 function testCanRedeemDepositedCollateral() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(dsce),amountCollateral);
    dsce.depositCollateralAndMintDsc(weth,amountCollateral,amountToMint);
    dsc.approve(address(dsce),amountToMint);
    dsce.redeemCollateralForDsc(weth,amountCollateral,amountToMint);
    vm.stopPrank();
    uint256 userbalance = dsc.balanceOf(user);
    assertEq(userbalance,0);
 }
 //healthFactor test
 function testProperlyReportsHealthFactor() public depositedCollateralAndMintedDsc{
    uint256 expectedHealthFactor = 100 ether;
    uint256 healthFactor = dsce.getHealthFactor(user);
    assertEq(healthFactor,expectedHealthFactor);
 }
 function testHealthFactorCanGoBelowOne()  public depositedCollateralAndMintedDsc {
    int256 ethUsdUpdatedPrice = 18e8;
    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
    uint256 userhealthFactor = dsce.getHealthFactor(user);
    assert(userhealthFactor == 0.9 ether);
 }
 //liquidation test
 function testMustImproveHealthFactorOnLiquidation() public {
    MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(ethUsdPriceFeed);
    tokenAddresses = [weth];
    priceFeedAddresses = [ethUsdPriceFeed];

    address owner = msg.sender;
    vm.prank(owner);
    DSCEngine mockDsce = new DSCEngine(tokenAddresses, priceFeedAddresses, address(mockDsc));
    mockDsc.transferOwnership(address(mockDsce));
    vm.startPrank(user);

    ERC20Mock(weth).approve(address(mockDsce),amountCollateral);
    mockDsce.depositCollateralAndMintDsc(weth,amountCollateral,amountToMint);
    vm.stopPrank();
    collateralToCover = 1 ether;
    ERC20Mock(weth).mint(liquidator,collateralToCover);
    vm.startPrank(liquidator);
    ERC20Mock(weth).approve(address(mockDsce),collateralToCover);
    uint256 debtToCover = 10 ether;
    mockDsce.depositCollateralAndMintDsc(weth,collateralToCover,amountToMint);
    mockDsc.approve(address(mockDsce),debtToCover);
    int256 ethUsdUpdatedPrice = 18e8;
    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
    vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
    mockDsce.liquidate(weth,user,debtToCover);
    vm.stopPrank();

 }
 function testCantLiquidateGoodHealthFactor() public depositedCollateralAndMintedDsc {
    ERC20Mock(weth).mint(liquidator,collateralToCover);
    vm.startPrank(liquidator);
    ERC20Mock(weth).approve(address(dsce),collateralToCover);
    dsce.depositCollateralAndMintDsc(weth,collateralToCover,amountToMint);
    dsc.approve(address(dsce),amountToMint);
    vm.stopPrank();
 }
 modifier liquidated() {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(dsce),amountCollateral);
    dsce.depositCollateralAndMintDsc(weth,amountCollateral,amountToMint);
    vm.stopPrank();
    int256 ethUsdUpdatedPrice = 18e8;
    MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
    uint256 userHealthFactor = dsce.getHealthFactor(user);
    ERC20Mock(weth).mint(liquidator,collateralToCover);
    vm.startPrank(liquidator);
    ERC20Mock(weth).approve(address(dsce),collateralToCover);
    dsce.depositCollateralAndMintDsc(weth,collateralToCover,amountToMint);
    dsc.approve(address(dsce),amountToMint);dsce.liquidate(weth,user,amountToMint);
    vm.stopPrank();
    _;

 }
 function testLiquidationPayoutInCorrect() public liquidated {
    uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);
    uint256 expectedWeth = dsce.getTokenAmountFromUsd(weth,amountToMint)+(dsce.getTokenAmountFromUsd(weth,amountToMint)/dsce.getLiquidationBonus());
    uint256 hardCodedExpected = 6111111111111111110;
    assertEq(liquidatorWethBalance,hardCodedExpected);
    assertEq(liquidatorWethBalance,expectedWeth);
 }
 function testUserStillHasSomeEthAfterLiquidation() public liquidated {
    uint256 amountLiquidated = dsce.getTokenAmountFromUsd(weth,amountToMint) + (dsce.getTokenAmountFromUsd(weth,amountToMint)/dsce.getLiquidationBonus());
    uint256 usdAmountLiquidated = dsce.getUsdValue(weth,amountLiquidated);
    uint256 expectedUserCollateralValueInUsd = dsce.getUsdValue(weth,amountCollateral)-(usdAmountLiquidated);
    (, uint256 userCollateralValueInUsd) = dsce.getAccountInformation(user);
    uint256 hardCodedExpectedValue = 70000000000000000020;
    assertEq(userCollateralValueInUsd, expectedUserCollateralValueInUsd);
    assertEq(userCollateralValueInUsd,hardCodedExpectedValue);
 }
 function testLiquidatorTakesOnUsersDebt() public liquidated {
    (uint256 liquidatorDscMinted,) = dsce.getAccountInformation(liquidator);
    assertEq(liquidatorDscMinted,amountToMint);
 }
 function testUserHasNoMoreDebt() public liquidated {
    (uint256 userDscMinted, ) = dsce.getAccountInformation(user);
    assertEq(userDscMinted,0);
 }
 //view and pure tests
function testGetCollateralTokenPriceFeed() public {
    address priceFeed = dsce.getCollateralTokenPriceFeed(weth);
    assertEq(priceFeed, ethUsdPriceFeed);
}
function testGetCollateralTokens() public {
    address[] memory collateralTokens = dsce.getCollateralTokens();
    assertEq(collateralTokens[0],weth);
}
function testGetMinHealthFactor() public {
    uint256 minHealthFactor = dsce.getMinHealthFactor();
    assertEq(minHealthFactor, MIN_HEALTH_FACTOR);
}
function testGetLiquidationThreshold() public {
    uint256 liquidationThreshold = dsce.getLiquidationThreshold();
    assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);

}
function testGetCollateralBalanceOfUser() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(dsce),amountCollateral);
    dsce.depositCollateral(weth,amountCollateral);
    vm.stopPrank();
    uint256 collateralBalance = dsce.getCollateralBalanceOfUser(user,weth);
    assertEq(collateralBalance,amountCollateral);

}
function testGetAccountCollateralValue() public {
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(dsce),amountCollateral);
    dsce.depositCollateral(weth,amountCollateral);
    vm.stopPrank();
    uint256 collateralValue = dsce.getAccountCollateralValue(user);
    uint256 expectedCollateralValue = dsce.getUsdValue(weth,amountCollateral);
    assertEq(collateralValue,expectedCollateralValue);
}
function testGetDsc() public {
    address dscAddress = dsce.getDsc();
    assertEq(dscAddress,address(dsc));
}
function testLiquidationPrecision() public {
    uint256 expectedLiquidationPrecision = 100;
    uint256 actualLiquidationPrecision = dsce.getLiquidationPrecision();
    assertEq(actualLiquidationPrecision,expectedLiquidationPrecision);
}




}