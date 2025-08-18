// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import {PriceUtils} from "../src/common/PriceUtils.sol";

contract TestPriceUtils is Test {
    function test_convertDecimals() external pure {
        assertEq(PriceUtils.convertDecimals(1, 1, 1), 1);
        assertEq(PriceUtils.convertDecimals(100, 2, 0), 1);
        assertEq(PriceUtils.convertDecimals(1, 0, 2), 100);

        assertEq(PriceUtils.convertDecimals(1000, 3, 0), 1);
        assertEq(PriceUtils.convertDecimals(1001, 3, 0), 2);
        assertEq(PriceUtils.convertDecimals(1999, 3, 0), 2);

        assertEq(PriceUtils.convertDecimals(1234_0000_0000, 8, 0), 1234);
    }

    function test_halving_pow2() external pure {
        for (uint256 i; i < 255; i++) {
            assertEq(PriceUtils.halving(1 << 255, 1, i), 1 << (255 - i));
        }
    }

    function test_halving_computed() external pure {
        assertEq(PriceUtils.halving(1424499730, 8906, 139967), 26462); // 26465 = -3 => e-4
        assertEq(PriceUtils.halving(25448394752, 3120, 28344), 46872731); // 46872559 = 172 => e-6
        assertEq(PriceUtils.halving(226801697741, 2055, 7691), 16944188740); // 16944070054 = 118686 => e-6
        assertEq(PriceUtils.halving(8346969424321, 2447, 14567), 134739948345); // 134739878463 = 69882 => e-7
        assertEq(PriceUtils.halving(45287518154421, 3882, 57451), 1588328639); // 1588313410 = 15229 => e-6
        assertEq(
            PriceUtils.halving(570920124541253, 9882, 107044),
            313151078238 // 313149809990 = 1268248 => e-6
        );
        assertEq(
            PriceUtils.halving(7645843420289247, 2217, 5130),
            1537665107975056 // 1537661454800508 = 3653174548 => e-6
        );
        assertEq(
            PriceUtils.halving(41496322237742742, 9631, 138777),
            1906996964267 // 1906978706870 = 18257397 => e-6
        );
        assertEq(
            PriceUtils.halving(324922745063857570, 3699, 14160),
            22878240879739585 // 22878035801573052 = 205078166533 => e-6
        );
        assertEq(
            PriceUtils.halving(7160344361217578864, 376, 2562),
            63645461810911484 // 63645361554348369 = 100256563115 => e-6
        );
        assertEq(
            PriceUtils.halving(48224578080290028571, 4891, 37054),
            252744870505318051 // 252742620367330313 = 2250137987738 => e-6
        );
        assertEq(
            PriceUtils.halving(105105524861191541746, 6259, 54700),
            245923975222518136 // 245923149907088301 = 825315429835 => e-6
        );
        assertEq(
            PriceUtils.halving(3099396934116196421933, 3511, 31839),
            5773426072293995295 // 5773376140217802275 = 49932076193020 => e-6
        );
        assertEq(
            PriceUtils.halving(26362372193702182792471, 4465, 32623),
            166549977597448035667 // 166549775208987485845 = 202388460549822 => e-6
        );
        assertEq(
            PriceUtils.halving(990909067413969805326317, 301, 3338),
            454678187455967549808 // 454675088014747167270 = 3099441220382538 => e-6
        );
        assertEq(
            PriceUtils.halving(3381740391629922203681908, 715, 10038),
            200878650042027568241 // 200877705112613028527 = 944929414539714 => e-6
        );
        assertEq(
            PriceUtils.halving(20690080805932031152205220, 7464, 53584),
            142781580193629410427449 // 142780897151513340316761 = 683042116070110688 => e-6
        );
        assertEq(
            PriceUtils.halving(997325693508064282098634698, 5823, 79101),
            81203875465712359043529 // 81203514400252740888790 = 361065459618154739 => e-6
        );
        assertEq(
            PriceUtils.halving(6654406976005663001193755017, 8615, 128040),
            223392455824911265372939 // 223391340970344010446350 = 1114854567254926589 => e-6
        );
        assertEq(
            PriceUtils.halving(63990819057295833822937117138, 5696, 9367),
            20468132231412279313226604986 // 20468105475107205357583938901 = 26756305073955642666085 => e-6
        );
        assertEq(
            PriceUtils.halving(944431998705134667255602102406, 7559, 79787),
            627671476720048668608848886 // 627666858068998984730219320 = 4618651049683878629566 => e-6
        );
    }
}
