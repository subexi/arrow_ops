import 'package:flutter_test/flutter_test.dart';

import 'package:arrow_ops/features/order/domain/paypal_fee_rules.dart';

void main() {
  group('PayPalFeeRules.rateByCountry', () {
    test('returns EEA rate for EEA country tokens', () {
      expect(PayPalFeeRules.rateByCountry('DE'), PayPalFeeRules.rateEea);
      expect(PayPalFeeRules.rateByCountry('deu'), PayPalFeeRules.rateEea);
      expect(PayPalFeeRules.rateByCountry('Germany'), PayPalFeeRules.rateEea);
      expect(PayPalFeeRules.rateByCountry('AT'), PayPalFeeRules.rateEea);
      expect(PayPalFeeRules.rateByCountry('NO'), PayPalFeeRules.rateEea);
      expect(PayPalFeeRules.rateByCountry('ISL'), PayPalFeeRules.rateEea);
      expect(PayPalFeeRules.rateByCountry('LIECHTENSTEIN'), PayPalFeeRules.rateEea);
    });

    test('returns UK rate for UK tokens', () {
      expect(PayPalFeeRules.rateByCountry('GB'), PayPalFeeRules.rateUk);
      expect(PayPalFeeRules.rateByCountry('uk'), PayPalFeeRules.rateUk);
      expect(
        PayPalFeeRules.rateByCountry('Vereinigtes Koenigreich'),
        PayPalFeeRules.rateUk,
      );
    });

    test('returns US/CA rate for US and Canada tokens', () {
      expect(PayPalFeeRules.rateByCountry('US'), PayPalFeeRules.rateUsCa);
      expect(PayPalFeeRules.rateByCountry('USA'), PayPalFeeRules.rateUsCa);
      expect(PayPalFeeRules.rateByCountry('CANADA'), PayPalFeeRules.rateUsCa);
      expect(PayPalFeeRules.rateByCountry('CA'), PayPalFeeRules.rateUsCa);
    });

    test('returns rest rate for non-EEA, non-UK, non-US/CA tokens', () {
      expect(PayPalFeeRules.rateByCountry('CH'), PayPalFeeRules.rateRest);
      expect(PayPalFeeRules.rateByCountry('JP'), PayPalFeeRules.rateRest);
      expect(PayPalFeeRules.rateByCountry(''), PayPalFeeRules.rateRest);
    });
  });

  group('PayPalFeeRules.feeFromBaseAmountEur', () {
    test('returns zero for non-positive base amounts', () {
      expect(
        PayPalFeeRules.feeFromBaseAmountEur(baseAmountEur: 0, countryToken: 'DE'),
        0,
      );
      expect(
        PayPalFeeRules.feeFromBaseAmountEur(baseAmountEur: -1, countryToken: 'DE'),
        0,
      );
    });

    test('calculates and rounds to 2 decimals', () {
      final fee = PayPalFeeRules.feeFromBaseAmountEur(
        baseAmountEur: 100,
        countryToken: 'DE',
      );
      // 100 * 0.0249 + 0.35 = 2.84
      expect(fee, 2.84);
    });

    test('uses country classification for rate selection', () {
      final feeUk = PayPalFeeRules.feeFromBaseAmountEur(
        baseAmountEur: 100,
        countryToken: 'GB',
      );
      final feeRest = PayPalFeeRules.feeFromBaseAmountEur(
        baseAmountEur: 100,
        countryToken: 'CH',
      );

      expect(feeUk, 4.13); // 100 * 0.0378 + 0.35 = 4.13
      expect(feeRest, 5.83); // 100 * 0.0548 + 0.35 = 5.83
    });
  });

  group('PayPalFeeRules.reverse calculation', () {
    test('calculates required received amount from net target', () {
      final required = PayPalFeeRules.requiredReceivedAmountFromNetTargetEur(
        netTargetEur: 100,
        countryToken: 'DE',
      );

      expect(required, 102.91);
    });

    test('calculates fee from net target using reverse approach', () {
      final fee = PayPalFeeRules.feeFromNetTargetEur(
        netTargetEur: 100,
        countryToken: 'GB',
      );

      expect(fee, 4.29);
    });

    test('returns zero in reverse calculation for non-positive target', () {
      expect(
        PayPalFeeRules.requiredReceivedAmountFromNetTargetEur(
          netTargetEur: 0,
          countryToken: 'DE',
        ),
        0,
      );
      expect(
        PayPalFeeRules.feeFromNetTargetEur(
          netTargetEur: -1,
          countryToken: 'DE',
        ),
        0,
      );
    });
  });
}
