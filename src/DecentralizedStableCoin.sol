//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;

/*@title decentralizedStableCoin
*@author HemaDevi
Collateral: Exogenous (ETH &BTC)
Minting : Alogirthemic
Relatcie Stability :Pegged to USD
*This contract is meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoinsystem
*/

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {


    //errors
    error DecentralizedStableCoin_MustBeMoreThanZero();
    error DecentralizedStableCoin_NotZeroAddress();
    error DecentralizedStableCoin_BurnAmountExceedsBalance();

    //functions
    constructor()
        ERC20("DecentrazlizedStableCoin", "DSC")
        
    {}


    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStableCoin_MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStableCoin_BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(
        address _to,
        uint256 _amount
    ) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin_NotZeroAddress();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin_MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
