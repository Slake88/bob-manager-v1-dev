import 'package:flutter_test/flutter_test.dart';
import 'package:bob_manager_mobile/core/module_definition.dart';
import 'package:bob_manager_mobile/repositories/financial_requests_repository.dart';

void main() {
  test('módulo Pedidos & Pagamentos está registado', () {
    expect(appModules.any((module) => module.code == 'financial'), isTrue);
  });

  test('estados elegíveis para cobranças são os estados ativos do clube', () {
    expect(FinancialRequestsRepository.isEligibleMemberStatus('active'), isTrue);
    expect(FinancialRequestsRepository.isEligibleMemberStatus('prospect'), isTrue);
    expect(FinancialRequestsRepository.isEligibleMemberStatus('full_color'), isTrue);
    expect(FinancialRequestsRepository.isEligibleMemberStatus('honorary'), isTrue);
    expect(FinancialRequestsRepository.isEligibleMemberStatus('suspended'), isFalse);
    expect(FinancialRequestsRepository.isEligibleMemberStatus('former'), isFalse);
    expect(FinancialRequestsRepository.isEligibleMemberStatus('deceased'), isFalse);
  });

  test('processos liquidados/rejeitados/cancelados são terminais', () {
    expect(FinancialRequestsRepository.isTerminalStatus('paid'), isTrue);
    expect(FinancialRequestsRepository.isTerminalStatus('rejected'), isTrue);
    expect(FinancialRequestsRepository.isTerminalStatus('cancelled'), isTrue);
    expect(FinancialRequestsRepository.isTerminalStatus('pending_review'), isFalse);
    expect(FinancialRequestsRepository.isTerminalStatus('awaiting_payment'), isFalse);
  });
}
