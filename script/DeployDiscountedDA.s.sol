// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.9;

import "@std/console.sol";
import "@std/Script.sol";

import "../src/HodlersDAExpSettlement.sol";
import "../src/test/MockDiscountCollection.sol";

contract DeployDiscountedDA is Script {

    HodlersDAExpSettlement Minter;

    function run() public {

        //uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_ANVIL");
        //vm.startBroadcast(deployerPrivateKey);
        vm.startBroadcast();

        address filter = 0x533D79A2669A22BAfeCdf1696aD6E738E4A2e07b;
        address genArt721Core = 0x41cc069871054C1EfB4Aa40aF12f673eA2b6a1fC;

        //address manifoldGenesisAddress = 0xEAC5e94C543cE2211B695bd69bd0D5ff3C4A21e1; // mainnet
        //address hodlersCollectivePassAddress = 0xD00495689D5161C511882364E0C342e12Dcc5f08; //mainnet

        address manifoldGenesisAddress = 0x417F4443e41611114E75B23Ef6D885e6CaB8854a; //Goerli
        address hodlersCollectivePassAddress = 0xC24129977F71fF506577ca689AAE571B33E5829c; //Goerli

        // SINCE GOERLI DOESN'T HAVE THE DISCOUNT PROJECTS, WE NEED TO DEPLOY MOCKS
        //MockDiscountCollection fakeManifoldGenesis = new MockDiscountCollection("Manifold Genesis", "MG"); 
        //MockDiscountCollection fakeHodlersCollectivePass = new MockDiscountCollection("Hodlers Collective Pass", "HCP");

        Minter = new HodlersDAExpSettlement(
            genArt721Core, 
            filter, 
            manifoldGenesisAddress,
            hodlersCollectivePassAddress  
        );

        // What you need to do manually after deployment
        //filter.addApprovedMinter(address(minter));
        //filter.setMinterForProject(projectId, address(minter));
        
        vm.stopBroadcast();

    }

}