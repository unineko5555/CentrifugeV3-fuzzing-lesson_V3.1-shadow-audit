// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.28;

import {Asserts} from "@chimera/Asserts.sol";
import {vm} from "@chimera/Hevm.sol";

import {Setup} from "../Setup.sol";
import {IAsyncVault} from "src/vaults/interfaces/IAsyncVault.sol";
import {IERC20Metadata} from "src/misc/interfaces/IERC20.sol";

/// @dev ERC-7540 Properties — reusable across projects
abstract contract AsyncVaultProperties is Setup, Asserts {
    uint256 MAX_ROUNDING_ERROR = 10 ** 18;

    /// @dev 7540-3 convertToAssets(totalSupply) == totalAssets unless price is 0
    function asyncVault_3(address asyncVaultTarget) public virtual {
        if (
            IAsyncVault(asyncVaultTarget).convertToAssets(
                10 ** IERC20Metadata(IAsyncVault(asyncVaultTarget).share()).decimals()
            ) == 0
        ) return;

        eq(
            IAsyncVault(asyncVaultTarget).convertToAssets(
                IERC20Metadata(IAsyncVault(asyncVaultTarget).share()).totalSupply()
            ),
            IAsyncVault(asyncVaultTarget).totalAssets(),
            "Property: 7540-3"
        );
    }

    /// @dev 7540-4 convertToShares(totalAssets) == totalSupply unless price is 0
    function asyncVault_4(address asyncVaultTarget) public virtual {
        if (
            IAsyncVault(asyncVaultTarget).convertToAssets(
                10 ** IERC20Metadata(IAsyncVault(asyncVaultTarget).share()).decimals()
            ) == 0
        ) return;

        lte(
            _diff(
                IAsyncVault(asyncVaultTarget).convertToShares(IAsyncVault(asyncVaultTarget).totalAssets()),
                IERC20Metadata(IAsyncVault(asyncVaultTarget).share()).totalSupply()
            ),
            MAX_ROUNDING_ERROR,
            "Property: 7540-4"
        );
    }

    /// @dev 7540-5 max* never reverts
    function asyncVault_5(address asyncVaultTarget) public virtual {
        try IAsyncVault(asyncVaultTarget).maxDeposit(_getActor()) {}
        catch {
            t(false, "Property: 7540-5 maxDeposit reverts");
        }
        try IAsyncVault(asyncVaultTarget).maxMint(_getActor()) {}
        catch {
            t(false, "Property: 7540-5 maxMint reverts");
        }
        try IAsyncVault(asyncVaultTarget).maxRedeem(_getActor()) {}
        catch {
            t(false, "Property: 7540-5 maxRedeem reverts");
        }
        try IAsyncVault(asyncVaultTarget).maxWithdraw(_getActor()) {}
        catch {
            t(false, "Property: 7540-5 maxWithdraw reverts");
        }
    }

    /// @dev 7540-6 claiming more than max always reverts
    function asyncVault_6_deposit(address asyncVaultTarget, uint256 amt) public virtual {
        if (amt == 0) return;
        uint256 maxDep = IAsyncVault(asyncVaultTarget).maxDeposit(_getActor());
        uint256 sum = maxDep + amt;
        if (sum == 0) return;
        if (sum < maxDep) return; // overflow guard

        try IAsyncVault(asyncVaultTarget).deposit(sum, _getActor()) {
            t(false, "Property: 7540-6 depositing more than max does not revert");
        } catch {
            return;
        }
        t(false, "Property: 7540-6 depositing more than max does not revert");
    }

    function asyncVault_6_mint(address asyncVaultTarget, uint256 amt) public virtual {
        if (amt == 0) return;
        uint256 maxDep = IAsyncVault(asyncVaultTarget).maxMint(_getActor());
        uint256 sum = maxDep + amt;
        if (sum == 0) return;
        if (sum < maxDep) return; // overflow guard

        try IAsyncVault(asyncVaultTarget).mint(sum, _getActor()) {
            t(false, "Property: 7540-6 minting more than max does not revert");
        } catch {
            return;
        }
        t(false, "Property: 7540-6 minting more than max does not revert");
    }

    function asyncVault_6_withdraw(address asyncVaultTarget, uint256 amt) public virtual {
        if (amt == 0) return;
        uint256 maxDep = IAsyncVault(asyncVaultTarget).maxWithdraw(_getActor());
        uint256 sum = maxDep + amt;
        if (sum == 0) return;
        if (sum < maxDep) return; // overflow guard

        try IAsyncVault(asyncVaultTarget).withdraw(sum, _getActor(), _getActor()) {
            t(false, "Property: 7540-6 withdrawing more than max does not revert");
        } catch {
            return;
        }
        t(false, "Property: 7540-6 withdrawing more than max does not revert");
    }

    function asyncVault_6_redeem(address asyncVaultTarget, uint256 amt) public virtual {
        if (amt == 0) return;
        uint256 maxDep = IAsyncVault(asyncVaultTarget).maxRedeem(_getActor());
        uint256 sum = maxDep + amt;
        if (sum == 0) return;
        if (sum < maxDep) return; // overflow guard

        try IAsyncVault(asyncVaultTarget).redeem(sum, _getActor(), _getActor()) {
            t(false, "Property: 7540-6 redeeming more than max does not revert");
        } catch {
            return;
        }
        t(false, "Property: 7540-6 redeeming more than max does not revert");
    }

    /// @dev 7540-7 requestRedeem reverts if share balance < amount
    function asyncVault_7(address asyncVaultTarget, uint256 shares) public virtual {
        if (shares == 0) return;
        uint256 actualBal = token.balanceOf(_getActor());
        uint256 balWeWillUse = actualBal + shares;
        if (balWeWillUse == 0) return;

        token.approve(address(asyncVaultTarget), 0);
        token.approve(address(asyncVaultTarget), type(uint256).max);

        try IAsyncVault(asyncVaultTarget).requestRedeem(balWeWillUse, _getActor(), _getActor()) {
            t(false, "Property: 7540-7 requestRedeem does not revert for shares > balance");
        } catch {
            return;
        }
        t(false, "Property: 7540-7 requestRedeem does not revert for shares > balance");
    }

    /// @dev 7540-8 preview* always reverts
    function asyncVault_8(address asyncVaultTarget) public virtual {
        try IAsyncVault(asyncVaultTarget).previewDeposit(0) {
            t(false, "Property: 7540-8 previewDeposit does not revert");
        } catch {}
        try IAsyncVault(asyncVaultTarget).previewMint(0) {
            t(false, "Property: 7540-8 previewMint does not revert");
        } catch {}
        try IAsyncVault(asyncVaultTarget).previewRedeem(0) {
            t(false, "Property: 7540-8 previewRedeem does not revert");
        } catch {}
        try IAsyncVault(asyncVaultTarget).previewWithdraw(0) {
            t(false, "Property: 7540-8 previewWithdraw does not revert");
        } catch {}
    }

    /// @dev 7540-9 if max[method] > 0, then [method](max) should not revert
    function asyncVault_9_deposit(address asyncVaultTarget) public virtual {
        uint256 maxDeposit = IAsyncVault(asyncVaultTarget).maxDeposit(_getActor());
        if (maxDeposit == 0) return;
        try IAsyncVault(asyncVaultTarget).deposit(maxDeposit, _getActor()) returns (uint256 shares) {
            sumOfClaimedDeposits[address(token)] += shares;
            return;
        } catch {
            t(false, "Property: 7540-9 max deposit reverts");
        }
    }

    function asyncVault_9_mint(address asyncVaultTarget) public virtual {
        uint256 maxMint = IAsyncVault(asyncVaultTarget).maxMint(_getActor());
        if (maxMint == 0) return;
        try IAsyncVault(asyncVaultTarget).mint(maxMint, _getActor()) {
            sumOfClaimedDeposits[address(token)] += maxMint;
        } catch {
            t(false, "Property: 7540-9 max mint reverts");
        }
    }

    function asyncVault_9_withdraw(address asyncVaultTarget) public virtual {
        uint256 maxWithdraw = IAsyncVault(asyncVaultTarget).maxWithdraw(_getActor());
        if (maxWithdraw == 0) return;
        try IAsyncVault(asyncVaultTarget).withdraw(maxWithdraw, _getActor(), _getActor()) {
            sumOfClaimedRedemptions[vault.asset()] += maxWithdraw;
        } catch {
            t(false, "Property: 7540-9 max withdraw reverts");
        }
    }

    function asyncVault_9_redeem(address asyncVaultTarget) public virtual {
        uint256 maxRedeem = IAsyncVault(asyncVaultTarget).maxRedeem(_getActor());
        if (maxRedeem == 0) return;
        try IAsyncVault(asyncVaultTarget).redeem(maxRedeem, _getActor(), _getActor()) returns (uint256 assets) {
            sumOfClaimedRedemptions[vault.asset()] += assets;
        } catch {
            t(false, "Property: 7540-9 max redeem reverts");
        }
    }

    function _diff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
