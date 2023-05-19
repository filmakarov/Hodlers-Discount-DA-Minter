// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "../src/HodlersDAExpSettlement.sol";
import "../src/Test/MockDiscountCollection.sol";
import "@artblocks/GenArt721CoreV3_Engine_Flex.sol";
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@std/Test.sol";
//import "@std/console.sol";

/**
 *   0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496 is default deployer 
 */

interface IFilterExtended {
    function mint(address to, uint256 projectId, address from) external;
    function genArt721CoreAddress() external returns (address);
    function addApprovedMinter(address _minterAddress) external;
    function getMinterForProject(uint256 _projectId) external view returns (address);
    function isApprovedMinter(address _minterAddress) external view returns (bool);
    function setMinterForProject(uint256 _projectId, address _minterAddress) external;
}

contract HodlersDutchAuctionWithDiscountsTestForked is Test {

    using ECDSA for bytes32;

    uint256 constant public ONE_HUNDRED_PERCENT = 100;
    uint256 constant public ZERO_DISCOUNT_TOKEN = 0;
    
    GenArt721CoreV3_Engine_Flex genArt721CoreV3;
    IFilterExtended filter;
    HodlersDAExpSettlement minter;
    MockDiscountCollection manifoldGenesis;
    MockDiscountCollection HCPass;
    IDelegationRegistry delegateCashRegistry;

    address deployer;

    uint256 projectId;

    address artistAddress;
    address abAdminAddress;
    address customer;

    uint256 auctionStartTime;
    uint256 priceDecayHalfLifeSeconds;
    uint256 startPrice;
    uint256 basePrice;

    uint256 goerliFork;

    function setUp() public {

        goerliFork = vm.createFork("https://rpc.ankr.com/eth_goerli");
        vm.selectFork(goerliFork);

        deployer = address(0xde9104e5);
        vm.deal(deployer, 1e21);

        abAdminAddress = address(0x8cc0019C16bced6891a96d32FF36FeAB4A663a40);

        filter = IFilterExtended(0x533D79A2669A22BAfeCdf1696aD6E738E4A2e07b);
        genArt721CoreV3 = GenArt721CoreV3_Engine_Flex(0x41cc069871054C1EfB4Aa40aF12f673eA2b6a1fC);
        delegateCashRegistry = IDelegationRegistry(0x00000000000076A84feF008CDAbe6409d2FE638B);

        projectId = genArt721CoreV3.nextProjectId();
        artistAddress = 0xe18Fc96ba325Ef22746aDA9A82d521845a2c16f8;
        vm.startPrank(abAdminAddress);
        genArt721CoreV3.addProject("TestProject", payable(artistAddress));
        vm.stopPrank();

        // Deploy contracts
        vm.startPrank(deployer);

        minter = new HodlersDAExpSettlement(address(genArt721CoreV3), address(filter));
        manifoldGenesis = new MockDiscountCollection("ManifoldGenesis", "MG");
        HCPass = new MockDiscountCollection("HCPass", "HCP");

        vm.stopPrank();

        // Add Minter as Approved to Filter
        vm.startPrank(0x8cc0019C16bced6891a96d32FF36FeAB4A663a40); //admin
        filter.addApprovedMinter(address(minter));
        filter.setMinterForProject(projectId, address(minter));

        // Configure Minter
        // Add discounts
        minter.setDiscountDataForCollection(projectId, address(manifoldGenesis), 50, 0);
        minter.setDiscountDataForCollection(projectId, address(HCPass), 25, 1000);
        minter.setDelegationRegistry(0x00000000000076A84feF008CDAbe6409d2FE638B);
        vm.stopPrank();

        // Set default auction details
        auctionStartTime = 1784328664;
        priceDecayHalfLifeSeconds = 350;
        startPrice = 1e18; // 1 eth
        basePrice = 1e17; // 0.1 eth

        customer = address(0xdecaf4a11ce);
        vm.deal(customer, 100*1e18);
        manifoldGenesis.mint(customer, 0);
        HCPass.mint(customer, 1000);
    }

    function testSetupSuccessful() public {
        (string memory projectName, , , , ) = genArt721CoreV3.projectDetails(projectId);
        assertEq(projectName, "TestProject");

        assertEq(filter.getMinterForProject(projectId), address(minter));
        assertEq(filter.isApprovedMinter(address(minter)), true);

        (uint256 discountPercentageMG, uint256 minTokenIdMG) = minter.discountCollections(projectId, address(manifoldGenesis));
        assertEq(discountPercentageMG, 50);
        assertEq(minTokenIdMG, 0);

        (uint256 discountPercentageHCP, uint256 minTokenIdHCP) = minter.discountCollections(projectId, address(HCPass));
        assertEq(discountPercentageHCP, 25);
        assertEq(minTokenIdHCP, 1000);

        assertEq(manifoldGenesis.balanceOf(customer), 1);
        assertEq(HCPass.balanceOf(customer), 1);
    }

    function canMintWithoutDiscount() public {
        activateProject(projectId);
        setupDefaultAuction(projectId);

        uint256 balanceOfCustomerBefore = genArt721CoreV3.balanceOf(customer);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);

        vm.warp(auctionStartTime + 1);
        vm.prank(customer);
        minter.purchaseTo_M6P{value: tokenPriceInWei}(customer, projectId, ZERO_DISCOUNT_TOKEN);

        assertEq(genArt721CoreV3.balanceOf(customer), balanceOfCustomerBefore + 1);
    }

    function testCanMintWithDiscount() public {
        activateProject(projectId);
        setupDefaultAuction(projectId);

        uint256 balanceOfCustomerBefore = genArt721CoreV3.balanceOf(customer);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);
        uint256 discountToken = buildDiscountToken(address(manifoldGenesis), 0);
        uint256 discountPercentage = minter.getDiscountPercentageForTokenForProject(projectId, discountToken);
        uint256 discountedPrice = tokenPriceInWei * (ONE_HUNDRED_PERCENT - discountPercentage) / ONE_HUNDRED_PERCENT;
          

        vm.warp(auctionStartTime + 1);
        vm.prank(customer);
        minter.purchaseTo_M6P{value: discountedPrice}(customer, projectId, discountToken);

        assertEq(genArt721CoreV3.balanceOf(customer), balanceOfCustomerBefore + 1);
    }

    // can not mint with the same discount token twice
    function testCanNotMintWithTheSameDiscountTokenTwice() public {
        activateProject(projectId);
        setupDefaultAuction(projectId);

        uint256 balanceOfCustomerBefore = genArt721CoreV3.balanceOf(customer);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);
        uint256 discountToken = buildDiscountToken(address(manifoldGenesis), 0);
        uint256 discountPercentage = minter.getDiscountPercentageForTokenForProject(projectId, discountToken);
        uint256 discountedPrice = tokenPriceInWei * (ONE_HUNDRED_PERCENT - discountPercentage) / ONE_HUNDRED_PERCENT; 

        // can purchase right after auction started
        vm.warp(auctionStartTime + 1);
        vm.startPrank(customer);
        minter.purchaseTo_M6P{value: discountedPrice}(customer, projectId, discountToken);

        // can not purchase again with the same discount token
        vm.expectRevert("Discount token already used");
        minter.purchaseTo_M6P{value: discountedPrice}(customer, projectId, discountToken);
        vm.stopPrank();

        assertEq(genArt721CoreV3.balanceOf(customer), balanceOfCustomerBefore + 1);
    }

    //trying to mint with discount token from collection that is not added to the project reverts
    function testCanNotMintIfCollectionNotAdded() public {
        activateProject(projectId);
        setupDefaultAuction(projectId);

        address darkHacker = address(0xda51c0de15);
        vm.deal(darkHacker, 1e19);

        MockDiscountCollection randomCollection = new MockDiscountCollection("RandomCollection", "RC");
        randomCollection.mint(darkHacker, 0);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);

        uint256 balanceOfCustomerBefore = genArt721CoreV3.balanceOf(customer);

        uint256 discountToken = buildDiscountToken(address(randomCollection), 0);
        uint256 discountedPrice = tokenPriceInWei * (ONE_HUNDRED_PERCENT - 50) / ONE_HUNDRED_PERCENT; 

        vm.warp(auctionStartTime + 1);
        vm.startPrank(darkHacker);
        vm.expectRevert("Invalid discount collection");
        minter.purchaseTo_M6P{value: discountedPrice}(customer, projectId, discountToken);
        assertEq(genArt721CoreV3.balanceOf(customer), balanceOfCustomerBefore);
        vm.stopPrank();
    }

    //can not mint with right discount token but wrong value sent
    function testCanNotWithRightDiscountTokenButWrongValueSent() public {
        activateProject(projectId);
        setupDefaultAuction(projectId);

        uint256 balanceOfCustomerBefore = genArt721CoreV3.balanceOf(customer);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);
        uint256 discountedPrice = tokenPriceInWei * (ONE_HUNDRED_PERCENT - 50) / ONE_HUNDRED_PERCENT; // 50% discount  
        uint256 discountToken = buildDiscountToken(address(HCPass), 1000);  //Provides only 25% discount

        vm.warp(auctionStartTime + 1);
        vm.startPrank(customer);
        vm.expectRevert("Must send minimum value to mint");
        minter.purchaseTo_M6P{value: discountedPrice}(customer, projectId, discountToken);
        vm.stopPrank();

        assertEq(genArt721CoreV3.balanceOf(customer), balanceOfCustomerBefore);
        assertFalse(minter.getWasTokenUsedForProject(projectId, discountToken));
    }

    // can not mint if token Id is not in range
    function testCanNotMintIfDiscountTokenIdIsNotInRange() public {
        activateProject(projectId);
        setupDefaultAuction(projectId);

        HCPass.mint(customer, 101);
        uint256 balanceOfCustomerBefore = genArt721CoreV3.balanceOf(customer);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);
        uint256 discountToken = buildDiscountToken(address(HCPass), 101);
        uint256 discountedPrice = tokenPriceInWei * (ONE_HUNDRED_PERCENT - 25) / ONE_HUNDRED_PERCENT; 

        vm.warp(auctionStartTime + 1);
        vm.startPrank(customer);
        vm.expectRevert("Invalid discount token id");
        minter.purchaseTo_M6P{value: discountedPrice}(customer, projectId, discountToken);
        vm.stopPrank();

        assertEq(genArt721CoreV3.balanceOf(customer), balanceOfCustomerBefore);
    }

    function testCanMintWithDiscountWhenDiscountTokenIdIsInRange() public {
        activateProject(projectId);
        setupDefaultAuction(projectId);

        uint256 balanceOfCustomerBefore = genArt721CoreV3.balanceOf(customer);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);
        uint256 discountToken = buildDiscountToken(address(HCPass), 1000);
        uint256 discountPercentage = minter.getDiscountPercentageForTokenForProject(projectId, discountToken);
        uint256 discountedPrice = tokenPriceInWei * (ONE_HUNDRED_PERCENT - discountPercentage) / ONE_HUNDRED_PERCENT;
          

        vm.warp(auctionStartTime + 1);
        vm.prank(customer);
        minter.purchaseTo_M6P{value: discountedPrice}(customer, projectId, discountToken);

        assertEq(genArt721CoreV3.balanceOf(customer), balanceOfCustomerBefore + 1);
    }

    // can not mint if discount token not owned neither delegated
    function testCanNotMintIfDiscountTokenNotOwnedNeitherDelegated() public {
        activateProject(projectId);
        setupDefaultAuction(projectId);

        address notCustomer = address(0xffffffeeeeeffff);
        vm.deal(notCustomer, 1e19);
        uint256 balanceOfNotCustomerBefore = genArt721CoreV3.balanceOf(notCustomer);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);
        uint256 discountToken = buildDiscountToken(address(manifoldGenesis), 0);
        uint256 discountPercentage = minter.getDiscountPercentageForTokenForProject(projectId, discountToken);
        uint256 discountedPrice = tokenPriceInWei * (ONE_HUNDRED_PERCENT - discountPercentage) / ONE_HUNDRED_PERCENT;

        vm.warp(auctionStartTime + 1);
        vm.startPrank(notCustomer);
        vm.expectRevert("Invalid discount token owner");
        minter.purchaseTo_M6P{value: discountedPrice}(customer, projectId, discountToken);
        vm.stopPrank();
        assertEq(genArt721CoreV3.balanceOf(notCustomer), balanceOfNotCustomerBefore);
    }

    // can mint using delegated token for discount
    function testCanMintWithDelegatedDiscount() public {

        activateProject(projectId);
        setupDefaultAuction(projectId);

        address vault = address(0xdeafbeefdeafbeef);
        address hotwallet = address(0xdecafdecaf);
        vm.deal(hotwallet, 1e19);
        HCPass.mint(vault, 1001);

        vm.prank(vault);
        delegateCashRegistry.delegateForAll(hotwallet, true);

        uint256 balanceOfHotwalletBefore = genArt721CoreV3.balanceOf(hotwallet);

        (, uint256 tokenPriceInWei, , ) = minter.getPriceInfo(projectId);
        uint256 discountedPrice = tokenPriceInWei * (ONE_HUNDRED_PERCENT - 25) / ONE_HUNDRED_PERCENT; // 25% discount  
        uint256 discountToken = buildDiscountToken(address(HCPass), 1001);  

        vm.warp(auctionStartTime + 1);
        vm.prank(hotwallet);
        minter.purchaseTo_M6P{value: discountedPrice}(hotwallet, projectId, discountToken);

        assertEq(genArt721CoreV3.balanceOf(hotwallet), balanceOfHotwalletBefore + 1);
    }

    function testNonAdminCanNotSetDiscounts() public {
        vm.prank(customer);
        vm.expectRevert("Only Artist or Admin ACL");
        minter.setDiscountDataForCollection(projectId, address(0x15a7d047), 25, 100);
    }

    // user can buy with deposit

    // user can get correct settlement amount when buying with discount and deposit after auction soldout

    // users can get correct settlement amount when buying with discount and deposit before auction soldout for several projects with one txn

    // users can claim settlements several times - before price has settled and then the rest after is has settled

    // admin can claim funds when collection is soldout at base price and users can get setllements correctly

    // admin can claim funds when collection is soldout higher that base price, and users can get setllements correctly

    // admin can claim funds when the price has settled but collection not soldout yet and sales will be going with instant sending of funds to admin and users can get settlements correctly



    // HELPERS

    function activateProject(uint256 _projectId) internal {
        vm.prank(abAdminAddress);
        genArt721CoreV3.toggleProjectIsActive(_projectId);

        vm.prank(artistAddress);
        genArt721CoreV3.toggleProjectIsPaused(_projectId);
        
        ( , , bool isActive, bool isPaused, , ) = genArt721CoreV3.projectStateData(_projectId); 
        assertEq(isActive, true);
        assertEq(isPaused, false);
    }

    function setupDefaultAuction(uint256 _projectId) internal {
        vm.prank(artistAddress);
        minter.setAuctionDetails(
            _projectId,
            auctionStartTime,
            priceDecayHalfLifeSeconds,    
            startPrice,    
            basePrice    
        );
    }

    function buildDiscountToken(address discountCollection, uint256 tokenId) public pure returns (uint256) {
        return (uint256(uint160(discountCollection)) << 96) + uint96(tokenId);
    }


}