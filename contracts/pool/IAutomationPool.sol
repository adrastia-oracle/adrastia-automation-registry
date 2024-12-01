// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {CommonErrors} from "./CommonErrors.sol";
import {CommonEvents} from "./CommonEvents.sol";
import {IAutomationPoolMinimal} from "./IAutomationPoolMinimal.sol";
import {IAutomationPoolStorage} from "./IAutomationPoolStorage.sol";
import {IBillingFacet} from "./facets/IBillingFacet.sol";
import {IWorkFacet} from "./facets/IWorkFacet.sol";

interface IAutomationPool is
    CommonEvents,
    CommonErrors,
    IAutomationPoolMinimal,
    IAutomationPoolStorage,
    IBillingFacet,
    IWorkFacet
{}
