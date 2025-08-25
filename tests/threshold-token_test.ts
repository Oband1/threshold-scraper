import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.5.4/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
  name: "Threshold Token: Can create a new token with specified parameters",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const token = chain.callReadOnlyFn(
      'threshold-token',
      'create-token',
      [
        types.uint(1000000),     // total supply
        types.uint(10000),        // distribution threshold
        types.uint(500),          // distribution rate (5%)
        types.uint(144),          // release frequency
        types.uint(52560),        // maturity blocks (~ 1 year)
        types.bool(false)         // allow early release
      ],
      deployer.address
    );

    // Check token creation result
    assertEquals(token.result.type, 'ok');
    assertEquals(token.result.value, 1n);  // First token ID
  }
});

Clarinet.test({
  name: "Threshold Token: Can purchase tokens in primary market",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const alice = accounts.get('wallet_1')!;

    // First, create a token
    const createToken = chain.callReadOnlyFn(
      'threshold-token',
      'create-token',
      [
        types.uint(1000000),
        types.uint(10000),
        types.uint(500),
        types.uint(144),
        types.uint(52560),
        types.bool(false)
      ],
      deployer.address
    );

    // Purchase tokens
    const tokenId = 1n;
    const purchase = chain.callReadOnlyFn(
      'threshold-token',
      'purchase-tokens',
      [
        types.uint(tokenId),
        types.uint(5),
        types.none()
      ],
      deployer.address
    );

    // Check purchase result
    assertEquals(purchase.result.type, 'ok');
    assertEquals(purchase.result.value, 5n);
  }
});

Clarinet.test({
  name: "Threshold Token: Cannot purchase more tokens than remaining supply",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;

    // Create token with small supply
    const createToken = chain.callReadOnlyFn(
      'threshold-token',
      'create-token',
      [
        types.uint(100000),      // lower total supply
        types.uint(10000),        
        types.uint(500),          
        types.uint(144),          
        types.uint(52560),        
        types.bool(false)         
      ],
      deployer.address
    );

    const tokenId = 1n;
    
    // Attempt to purchase more tokens than total supply
    const purchase = chain.callReadOnlyFn(
      'threshold-token',
      'purchase-tokens',
      [
        types.uint(tokenId),
        types.uint(20),  // More than available supply
        types.none()
      ],
      deployer.address
    );

    // Check purchase failure
    assertEquals(purchase.result.type, 'err');
    assertEquals(purchase.result.value, 104n);  // TOKEN-ALLOCATION-EXHAUSTED error code
  }
});